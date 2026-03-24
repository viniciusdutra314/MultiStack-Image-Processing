const std = @import("std");
const my_lib = @import("ImageProcessing");
const rl = @import("raylib");
const rg = @import("raygui");

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
            const transformed = @min(@max(ctx.a * (val_f * ctx.b), 0.0), 255.0);
            const final: u8 = @intFromFloat(transformed);
            ctx.processed_pixels[i][0] = final;
            ctx.histogram[final] += 1;
        } else {
            ctx.processed_pixels[i][0] = 0;
        }
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

    const original_img = try read_as_gray: {
        const rgb_attempt = my_lib.Netpbm.readNetbpmFromFilePathAs(
            my_lib.Image(.rgb, u8, .interleaved),
            allocator,
            args[1],
        );

        if (rgb_attempt) |img| {
            const gray_img = try img.toGrayscale(allocator);
            img.deinit(allocator);
            break :read_as_gray gray_img;
        } else |err| {
            if (err == my_lib.Netpbm.PgmError.IncompatibleOutputImageType) {
                break :read_as_gray try my_lib.Netpbm.readNetbpmFromFilePathAs(
                    my_lib.Image(.grayscale, u8, .interleaved),
                    allocator,
                    args[1],
                );
            }
            break :read_as_gray err;
        }
    };
    defer original_img.deinit(allocator);

    var processed_img = try my_lib.Image(.grayscale, u8, .interleaved).init(allocator, original_img.width, original_img.height);
    defer processed_img.deinit(allocator);

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(1280, 720, "Processamento de Imagem Multithreaded");
    defer rl.closeWindow();

    const texture = try rl.loadTextureFromImage(.{
        .data = @ptrCast(processed_img.getSliceMut()),
        .width = @intCast(processed_img.width),
        .height = @intCast(processed_img.height),
        .mipmaps = 1,
        .format = .uncompressed_grayscale,
    });
    defer rl.unloadTexture(texture);

    const original_texture = try rl.loadTextureFromImage(.{
        .data = @ptrCast(@constCast(original_img.getSlice())),
        .width = @intCast(original_img.width),
        .height = @intCast(original_img.height),
        .mipmaps = 1,
        .format = .uncompressed_grayscale,
    });
    defer rl.unloadTexture(original_texture);

    var a_slider: f32 = 1.0;
    var b_slider: f32 = 0.0;
    var threshold_slider: f32 = 0.0;
    var normalize_histogram = false;
    var equalize = false;

    const thread_count = std.Thread.getCpuCount() catch 4;
    const contexts = try allocator.alloc(ThreadContext, thread_count);
    defer allocator.free(contexts);
    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var iterations: u32 = 0;
    var total_time: f64 = 0.0;

    while (!rl.windowShouldClose()) {
        const start_time = std.time.nanoTimestamp();

        const pixels_per_thread = original_img.data.len / thread_count;
        var histogram = [_]usize{0} ** 256;

        for (0..thread_count) |i| {
            contexts[i] = .{
                .original_pixels = original_img.getSlice(),
                .processed_pixels = processed_img.getSliceMut(),
                .start_index = i * pixels_per_thread,
                .end_index = if (i == thread_count - 1) original_img.data.len else (i + 1) * pixels_per_thread,
                .a = a_slider,
                .b = b_slider,
                .threshold = threshold_slider,
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

        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000.0;
        total_time += duration_ms;
        iterations += 1;
        if (iterations % 100 == 0) {
            std.debug.print("Avg processing time ({d} threads): {d:.4} ms\n", .{ thread_count, total_time / @as(f64, @floatFromInt(iterations)) });
        }

        rl.beginDrawing();
        rl.clearBackground(.ray_white);

        var max_hist: usize = 0;
        var total_pixels: usize = 0;
        for (histogram) |h| {
            if (h > max_hist) {
                max_hist = h;
            }
            total_pixels += h;
        }
        var cdf = [_]f32{0.0} ** 256;
        if (total_pixels > 0) {
            var sum: usize = 0;
            for (0..256) |i| {
                sum += histogram[i];
                cdf[i] = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(total_pixels));
            }
        }
        if (equalize) {
            for (processed_img.getSliceMut()) |*pixel| {
                pixel[0] = @intFromFloat(cdf[pixel[0]] * 255.0);
            }
        }
        rl.updateTexture(texture, processed_img.getSlice().ptr);

        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        const section_w = screen_w / 3.0;
        const screen_padding: f32 = 80.0;
        const scale = @min((section_w - 60.0) / @as(f32, @floatFromInt(original_img.width)), (screen_h * 0.5) / @as(f32, @floatFromInt(original_img.height)));
        const display_w = @as(f32, @floatFromInt(original_img.width)) * scale;
        const display_h = @as(f32, @floatFromInt(original_img.height)) * scale;

        rl.drawTexturePro(original_texture, .{ .x = 0, .y = 0, .width = @floatFromInt(original_texture.width), .height = @floatFromInt(original_texture.height) }, .{ .x = section_w + (section_w - display_w) / 2, .y = 60, .width = display_w, .height = display_h }, .{ .x = 0, .y = 0 }, 0, .white);
        rl.drawText("Original", @intFromFloat(section_w + screen_padding), 20, 24, rl.Color.black);
        rl.drawTexturePro(texture, .{ .x = 0, .y = 0, .width = @floatFromInt(texture.width), .height = @floatFromInt(texture.height) }, .{ .x = (section_w * 2) + (section_w - display_w) / 2, .y = 60, .width = display_w, .height = display_h }, .{ .x = 0, .y = 0 }, 0, .white);
        rl.drawText("Processada", @intFromFloat(section_w * 2.0 + screen_padding), 20, 24, rl.Color.black);

        const hist_x: f32 = screen_padding;
        const hist_h: f32 = screen_h * 0.5;
        const hist_y: f32 = 60;
        const hist_w: f32 = section_w - 60;

        rl.drawText("Histograma", @intFromFloat(hist_x), 20, 24, rl.Color.black);
        rl.drawRectangleLinesEx(.{ .x = hist_x, .y = 60, .width = hist_w, .height = hist_w }, 2, rl.Color.gray);
        const label_count = 10;
        for (0..label_count) |i| {
            const val = i * (255 / (label_count - 1));
            var buf: [4:0]u8 = undefined;
            const text = try std.fmt.bufPrintZ(&buf, "{d}", .{val});
            const x_pos = hist_x + (@as(f32, @floatFromInt(val)) / 256.0) * hist_w;
            rl.drawText(text, @intFromFloat(x_pos - 10), @intFromFloat(hist_y + hist_h + 5), 16, rl.Color.black);
        }
        const y_label_count = 5;
        for (0..y_label_count) |i| {
            var buf: [16:0]u8 = undefined;
            const text = if (normalize_histogram and total_pixels > 0) blk: {
                const prob = (@as(f32, @floatFromInt(max_hist)) / @as(f32, @floatFromInt(total_pixels))) * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(y_label_count - 1)));
                break :blk try std.fmt.bufPrintZ(&buf, "{d:.3}", .{prob});
            } else blk: {
                const val = (max_hist * i) / (y_label_count - 1);
                break :blk try std.fmt.bufPrintZ(&buf, "{d}", .{val});
            };

            const y_pos = (hist_y + hist_h) - (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(y_label_count - 1))) * hist_h;
            const text_w = rl.measureText(text, 12);
            rl.drawText(text, @intFromFloat(hist_x - @as(f32, @floatFromInt(text_w)) - 5), @intFromFloat(y_pos - 6), 12, rl.Color.black);
        }

        for (histogram, 0..) |count, i| {
            if (count == 0 or max_hist == 0) continue;
            const bar_h = (@as(f32, @floatFromInt(count)) / @as(f32, @floatFromInt(max_hist))) * hist_h;
            rl.drawLineEx(.{ .x = hist_x + (@as(f32, @floatFromInt(i)) / 256.0) * hist_w, .y = 60 + hist_h }, .{ .x = hist_x + (@as(f32, @floatFromInt(i)) / 256.0) * hist_w, .y = 60 + hist_h - bar_h }, 1, .red);
        }

        const slider_x = screen_w / 2 - section_w / 2;
        const start_y = screen_h * 0.65;

        var label_buf: [64:0]u8 = undefined;
        const a_label = try std.fmt.bufPrintZ(&label_buf, "Contraste (a={d:.2})", .{a_slider});
        _ = rg.slider(.{ .x = slider_x, .y = start_y, .width = section_w, .height = 30 }, "", a_label, &a_slider, 0.0, 10.0);
        const b_label = try std.fmt.bufPrintZ(&label_buf, "Brilho (b={d:.2})", .{b_slider});
        _ = rg.slider(.{ .x = slider_x, .y = start_y + 40, .width = section_w, .height = 30 }, "", b_label, &b_slider, -255.0, 255.0);
        const threshold_label = try std.fmt.bufPrintZ(&label_buf, "Limiar (t={d:.2})", .{threshold_slider});
        _ = rg.slider(.{ .x = slider_x, .y = start_y + 80, .width = section_w, .height = 30 }, "", threshold_label, &threshold_slider, 0.0, 255.0);

        if (rg.button(.{ .x = slider_x, .y = start_y + 120, .width = section_w, .height = 30 }, "Resetar")) {
            a_slider = 1.0;
            b_slider = 0.0;
            threshold_slider = 0.0;
            normalize_histogram = false;
            equalize = false;
        }

        const pdf_btn_text = if (normalize_histogram) "Modo: Histograma (Normalizado)" else "Modo: Contagem (Frequência)";
        if (rg.button(.{ .x = slider_x, .y = start_y + 160, .width = section_w, .height = 30 }, pdf_btn_text)) {
            normalize_histogram = !normalize_histogram;
        }
        const equalize_text = if (equalize) "Equalizado" else "Não equalizado";

        if (rg.button(.{ .x = slider_x, .y = start_y + 200, .width = section_w, .height = 30 }, equalize_text)) {
            equalize = !equalize;
        }
        rl.endDrawing();
    }
}
