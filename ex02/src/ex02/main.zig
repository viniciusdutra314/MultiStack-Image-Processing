const std = @import("std");
const my_lib = @import("ImageProcessing");
const rl = @import("raylib");
const rg = @import("raygui");

const GrayImage = my_lib.Image(.grayscale, u8, .interleaved);

const LABEL_COUNT_X = 10;
const LABEL_COUNT_Y = 5;

const UiState = struct {
    a_slider: f32 = 1.0,
    b_slider: f32 = 0.0,
    threshold_slider: f32 = 0.0,
    normalize_histogram: bool = false,
    equalize: bool = false,
};

const RenderLayout = struct {
    screen_w: f32,
    screen_h: f32,
    section_w: f32,
    screen_padding: f32,
    scale: f32,
    display_w: f32,
    display_h: f32,
    hist_x: f32,
    hist_y: f32,
    hist_w: f32,
    hist_h: f32,
    slider_x: f32,
    slider_start_y: f32,
};

const HistogramStats = struct {
    max_hist: usize,
    total_pixels: usize,
};

const ThreadContext = struct {
    original_pixels: []const [1]u8,
    processed_pixels: [][1]u8,
    start_index: usize,
    end_index: usize,
    a: f32,
    b: f32,
    threshold: f32,
    histogram: [256]usize,
};

fn processImagePart(ctx: *ThreadContext) void {
    const simd_size = std.simd.suggestVectorLength(u8) orelse 16;
    const VectorU8 = @Vector(simd_size, u8);
    const VectorF32 = @Vector(simd_size, f32);

    const v_a: VectorF32 = @splat(ctx.a);
    const v_b: VectorF32 = @splat(ctx.b);
    const threshold_v: VectorF32 = @splat(ctx.threshold);
    const v_0: VectorF32 = @splat(0.0);
    const v_255: VectorF32 = @splat(255.0);

    var i = ctx.start_index;
    while (i + simd_size <= ctx.end_index) : (i += simd_size) {
        const slice = ctx.original_pixels[i..][0..simd_size];
        const v_pixels: VectorU8 = @as(*const [simd_size]u8, @ptrCast(slice)).*;

        var v_float: VectorF32 = @floatFromInt(v_pixels);
        const mask = v_float >= threshold_v;
        v_float = v_a * (v_float + v_b);
        v_float = @min(@max(v_float, v_0), v_255);

        const v_transformed: VectorU8 = @intFromFloat(v_float);
        const v_final = @select(u8, mask, v_transformed, @as(VectorU8, @splat(0)));

        @as(*[simd_size]u8, @ptrCast(ctx.processed_pixels[i..][0..simd_size].ptr)).* = v_final;

        for (0..simd_size) |j| {
            if (mask[j]) {
                ctx.histogram[v_final[j]] += 1;
            }
        }
    }

    while (i < ctx.end_index) : (i += 1) {
        const val_f: f32 = @floatFromInt(ctx.original_pixels[i][0]);
        if (val_f >= ctx.threshold) {
            const transformed = @min(@max(ctx.a * (val_f + ctx.b), 0.0), 255.0);
            const final: u8 = @intFromFloat(transformed);
            ctx.processed_pixels[i][0] = final;
            ctx.histogram[final] += 1;
        } else {
            ctx.processed_pixels[i][0] = 0;
        }
    }
}

fn parseInputImage(allocator: std.mem.Allocator, path: []const u8) !GrayImage {
    const rgb_attempt = my_lib.Netpbm.readNetbpmFromFilePathAs(
        my_lib.Image(.rgb, u8, .interleaved),
        allocator,
        path,
    );

    if (rgb_attempt) |img| {
        const gray_img = try img.toGrayscale(allocator);
        img.deinit(allocator);
        return gray_img;
    } else |err| {
        if (err == my_lib.Netpbm.PgmError.IncompatibleOutputImageType) {
            return my_lib.Netpbm.readNetbpmFromFilePathAs(
                GrayImage,
                allocator,
                path,
            );
        }
        return err;
    }
}

fn initTextureFromGrayImage(img: GrayImage) !rl.Texture2D {
    return rl.loadTextureFromImage(.{
        .data = @ptrCast(@constCast(img.getSlice())),
        .width = @intCast(img.width),
        .height = @intCast(img.height),
        .mipmaps = 1,
        .format = .uncompressed_grayscale,
    });
}

fn computeLayout(original_img: GrayImage) RenderLayout {
    const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
    const section_w = screen_w / 3.0;
    const screen_padding: f32 = 80.0;

    const scale = @min(
        (section_w - 60.0) / @as(f32, @floatFromInt(original_img.width)),
        (screen_h * 0.5) / @as(f32, @floatFromInt(original_img.height)),
    );
    const display_w = @as(f32, @floatFromInt(original_img.width)) * scale;
    const display_h = @as(f32, @floatFromInt(original_img.height)) * scale;

    return .{
        .screen_w = screen_w,
        .screen_h = screen_h,
        .section_w = section_w,
        .screen_padding = screen_padding,
        .scale = scale,
        .display_w = display_w,
        .display_h = display_h,
        .hist_x = screen_padding,
        .hist_y = screen_padding,
        .hist_w = section_w * 0.8,
        .hist_h = screen_h * 0.5,
        .slider_x = screen_w / 2 - section_w / 2,
        .slider_start_y = screen_h * 0.65,
    };
}

fn processMultithreaded(
    original_img: GrayImage,
    processed_img: *GrayImage,
    ui: UiState,
    contexts: []ThreadContext,
    threads: []std.Thread,
    histogram: *[256]usize,
) !void {
    histogram.* = [_]usize{0} ** 256;
    const thread_count = contexts.len;
    const pixels_per_thread = original_img.data.len() / thread_count;

    for (0..thread_count) |i| {
        contexts[i] = .{
            .original_pixels = original_img.getSlice(),
            .processed_pixels = processed_img.getSliceMut(),
            .start_index = i * pixels_per_thread,
            .end_index = if (i == thread_count - 1) original_img.data.len() else (i + 1) * pixels_per_thread,
            .a = ui.a_slider,
            .b = ui.b_slider,
            .threshold = ui.threshold_slider,
            .histogram = [_]usize{0} ** 256,
        };
        threads[i] = try std.Thread.spawn(.{}, processImagePart, .{&contexts[i]});
    }

    for (threads) |t| t.join();

    for (contexts) |ctx| {
        for (ctx.histogram, 0..) |count, i| {
            histogram[i] += count;
        }
    }
}

fn calcHistogramStats(histogram: *const [256]usize) HistogramStats {
    var max_hist: usize = 0;
    var total_pixels: usize = 0;

    for (histogram) |h| {
        if (h > max_hist) max_hist = h;
        total_pixels += h;
    }

    return .{
        .max_hist = max_hist,
        .total_pixels = total_pixels,
    };
}

fn buildCdf(histogram: *const [256]usize, total_pixels: usize) [256]f32 {
    var cdf = [_]f32{0.0} ** 256;
    if (total_pixels == 0) return cdf;

    var sum: usize = 0;
    for (0..256) |i| {
        sum += histogram[i];
        cdf[i] = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(total_pixels));
    }
    return cdf;
}

fn applyEqualization(processed_img: *GrayImage, cdf: *const [256]f32) void {
    for (processed_img.getSliceMut()) |*pixel| {
        pixel[0] = @intFromFloat(cdf[pixel[0]] * 255.0);
    }
}

fn drawImages(layout: RenderLayout, original_texture: rl.Texture2D, processed_texture: rl.Texture2D) void {
    rl.drawTexturePro(
        original_texture,
        .{ .x = 0, .y = 0, .width = @floatFromInt(original_texture.width), .height = @floatFromInt(original_texture.height) },
        .{ .x = layout.section_w + (layout.section_w - layout.display_w) / 2, .y = 60, .width = layout.display_w, .height = layout.display_h },
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );
    rl.drawText("Original", @intFromFloat(layout.section_w + layout.screen_padding), 20, 24, rl.Color.black);

    rl.drawTexturePro(
        processed_texture,
        .{ .x = 0, .y = 0, .width = @floatFromInt(processed_texture.width), .height = @floatFromInt(processed_texture.height) },
        .{ .x = (layout.section_w * 2) + (layout.section_w - layout.display_w) / 2, .y = 60, .width = layout.display_w, .height = layout.display_h },
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );
    rl.drawText("Processada", @intFromFloat(layout.section_w * 2.0 + layout.screen_padding), 20, 24, rl.Color.black);
}

fn drawHistogram(layout: RenderLayout, histogram: *const [256]usize, stats: HistogramStats, normalize_histogram: bool) !void {
    rl.drawText("Histograma", @intFromFloat(layout.hist_x), 20, 24, rl.Color.black);
    rl.drawRectangleLinesEx(
        .{ .x = layout.hist_x, .y = layout.hist_y, .width = layout.hist_w, .height = layout.hist_h },
        2,
        rl.Color.gray,
    );

    for (0..LABEL_COUNT_X) |i| {
        const val = i * (255 / (LABEL_COUNT_X - 1));
        var buf: [4:0]u8 = undefined;
        const text = try std.fmt.bufPrintZ(&buf, "{d}", .{val});
        const x_pos = layout.hist_x + (@as(f32, @floatFromInt(val)) / 255.0) * layout.hist_w;
        rl.drawText(text, @intFromFloat(x_pos - 10), @intFromFloat(layout.hist_y + layout.hist_h + 5), 16, rl.Color.black);
    }

    for (0..LABEL_COUNT_Y) |i| {
        var buf: [16:0]u8 = undefined;
        const text = if (normalize_histogram and stats.total_pixels > 0) blk: {
            const prob =
                (@as(f32, @floatFromInt(stats.max_hist)) / @as(f32, @floatFromInt(stats.total_pixels))) *
                (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(LABEL_COUNT_Y - 1)));
            break :blk try std.fmt.bufPrintZ(&buf, "{d:.3}", .{prob});
        } else blk: {
            const val = (stats.max_hist * i) / (LABEL_COUNT_Y - 1);
            break :blk try std.fmt.bufPrintZ(&buf, "{d}", .{val});
        };

        const y_pos =
            (layout.hist_y + layout.hist_h) -
            (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(LABEL_COUNT_Y - 1))) * layout.hist_h;
        const text_w = rl.measureText(text, 12);
        rl.drawText(
            text,
            @intFromFloat(layout.hist_x - @as(f32, @floatFromInt(text_w)) - 5),
            @intFromFloat(y_pos - 6),
            12,
            rl.Color.black,
        );
    }

    for (histogram, 0..) |count, i| {
        if (count == 0 or stats.max_hist == 0) continue;
        const bar_h = (@as(f32, @floatFromInt(count)) / @as(f32, @floatFromInt(stats.max_hist))) * layout.hist_h;
        const x = layout.hist_x + (@as(f32, @floatFromInt(i)) / 255.0) * layout.hist_w;
        rl.drawLineEx(
            .{ .x = x, .y = layout.hist_y + layout.hist_h },
            .{ .x = x, .y = layout.hist_y + layout.hist_h - bar_h },
            1,
            .red,
        );
    }
}

fn drawControls(layout: RenderLayout, ui: *UiState) !void {
    var label_buf: [64:0]u8 = undefined;

    const a_label = try std.fmt.bufPrintZ(&label_buf, "Contraste (a={d:.2})", .{ui.a_slider});
    _ = rg.slider(
        .{ .x = layout.slider_x, .y = layout.slider_start_y, .width = layout.section_w, .height = 30 },
        "",
        a_label,
        &ui.a_slider,
        0.0,
        10.0,
    );

    const b_label = try std.fmt.bufPrintZ(&label_buf, "Brilho (b={d:.2})", .{ui.b_slider});
    _ = rg.slider(
        .{ .x = layout.slider_x, .y = layout.slider_start_y + 40, .width = layout.section_w, .height = 30 },
        "",
        b_label,
        &ui.b_slider,
        -255.0,
        255.0,
    );

    const threshold_label = try std.fmt.bufPrintZ(&label_buf, "Limiar (t={d:.2})", .{ui.threshold_slider});
    _ = rg.slider(
        .{ .x = layout.slider_x, .y = layout.slider_start_y + 80, .width = layout.section_w, .height = 30 },
        "",
        threshold_label,
        &ui.threshold_slider,
        0.0,
        255.0,
    );

    if (rg.button(
        .{ .x = layout.slider_x, .y = layout.slider_start_y + 120, .width = layout.section_w, .height = 30 },
        "Resetar",
    )) {
        ui.* = .{};
    }

    const hist_btn = if (ui.normalize_histogram) "Modo: Histograma (Normalizado)" else "Modo: Contagem (Frequência)";
    if (rg.button(
        .{ .x = layout.slider_x, .y = layout.slider_start_y + 160, .width = layout.section_w, .height = 30 },
        hist_btn,
    )) {
        ui.normalize_histogram = !ui.normalize_histogram;
    }

    const equalize_btn = if (ui.equalize) "Equalizado" else "Não equalizado";
    if (rg.button(
        .{ .x = layout.slider_x, .y = layout.slider_start_y + 200, .width = layout.section_w, .height = 30 },
        equalize_btn,
    )) {
        ui.equalize = !ui.equalize;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Uso: ex02 <caminho_para_o_arquivo>\n", .{});
        return;
    }

    const original_img = try parseInputImage(allocator, args[1]);
    defer original_img.deinit(allocator);

    var processed_img = try GrayImage.init(allocator, original_img.width, original_img.height);
    defer processed_img.deinit(allocator);

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(1280, 720, "Processamento de Imagem");
    defer rl.closeWindow();

    const texture = try initTextureFromGrayImage(processed_img);
    defer rl.unloadTexture(texture);

    const original_texture = try initTextureFromGrayImage(original_img);
    defer rl.unloadTexture(original_texture);

    var ui = UiState{};

    const thread_count = std.Thread.getCpuCount() catch 4;
    const contexts = try allocator.alloc(ThreadContext, thread_count);
    defer allocator.free(contexts);

    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var iterations: u32 = 0;
    var total_time: f64 = 0.0;

    while (!rl.windowShouldClose()) {
        const start_time = std.time.nanoTimestamp();

        var histogram = [_]usize{0} ** 256;
        try processMultithreaded(original_img, &processed_img, ui, contexts, threads, &histogram);

        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000.0;
        total_time += duration_ms;
        iterations += 1;
        if (iterations % 100 == 0) {
            std.debug.print(
                "Avg processing time ({d} threads): {d:.4} ms\n",
                .{ thread_count, total_time / @as(f64, @floatFromInt(iterations)) },
            );
        }

        const stats = calcHistogramStats(&histogram);
        const cdf = buildCdf(&histogram, stats.total_pixels);
        if (ui.equalize) {
            applyEqualization(&processed_img, &cdf);
            histogram = [_]usize{0} ** 256;
            try processMultithreaded(processed_img, &processed_img, UiState{}, contexts, threads, &histogram);
        }

        rl.updateTexture(texture, processed_img.getSlice().ptr);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        const layout = computeLayout(original_img);
        drawImages(layout, original_texture, texture);
        try drawHistogram(layout, &histogram, stats, ui.normalize_histogram);
        try drawControls(layout, &ui);
    }
}
