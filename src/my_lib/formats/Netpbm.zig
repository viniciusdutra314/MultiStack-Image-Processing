const std = @import("std");
const my_lib = @import("../my_lib.zig");
const Image = my_lib.Image;
const ConversionPolicy = my_lib.ConversionPolicy;

pub const PgmError = error{
    InvalidMagicNumber,
    InvalidHeader,
    UnsupportedFormat,
    AllocationFailed,
    EndOfStream,
    IncompatibleOutputImageType,
};

fn readNextToken(reader: *std.Io.Reader, buf: []u8) ![]const u8 {
    var i: usize = 0;
    while (true) {
        const b = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (i > 0) return buf[0..i];
                return error.EndOfStream;
            },
            else => return err,
        };

        if (b == '#') {
            if (i > 0) return buf[0..i];
            while (true) {
                const cb = reader.takeByte() catch |err| switch (err) {
                    error.EndOfStream => return error.EndOfStream,
                    else => return err,
                };
                if (cb == '\n') break;
            }
            continue;
        }

        if (std.ascii.isWhitespace(b)) {
            if (i > 0) return buf[0..i];
            continue;
        }

        if (i < buf.len) {
            buf[i] = b;
            i += 1;
        } else {
            return error.TokenTooLong;
        }
    }
}

fn parseNextInt(reader: *std.Io.Reader, buffer: []u8) !usize {
    const token = try readNextToken(reader, buffer);
    return std.fmt.parseInt(usize, token, 10);
}

pub fn readNetbpmFromFilePathAs(comptime T: type, allocator: std.mem.Allocator, filepath: []const u8) !T {
    const file = try std.fs.cwd().openFile(filepath, .{});
    var buffer: [1024]u8 = undefined;
    var reader_file = file.reader(&buffer);
    return try readNetbpmFromReaderAs(T, allocator, &reader_file.interface);
}

pub fn readNetbpmFromReaderAs(
    comptime T: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) !T {
    var buffer: [64]u8 = undefined;
    const magic = try readNextToken(reader, &buffer);
    const is_pgm = std.mem.eql(u8, magic, "P2") or std.mem.eql(u8, magic, "P5");
    const is_ppm = std.mem.eql(u8, magic, "P3") or std.mem.eql(u8, magic, "P6");
    if (!is_pgm and !is_ppm) {
        return PgmError.InvalidMagicNumber;
    }
    if (is_pgm and T.colorspace != my_lib.ColorSpace.grayscale) {
        return PgmError.IncompatibleOutputImageType;
    }
    if (is_ppm and T.colorspace != my_lib.ColorSpace.rgb) {
        return PgmError.IncompatibleOutputImageType;
    }
    const is_ascii = std.mem.eql(u8, magic, "P2") or std.mem.eql(u8, magic, "P3");
    const width = try parseNextInt(reader, &buffer);
    const height = try parseNextInt(reader, &buffer);
    const max_val = try parseNextInt(reader, &buffer);
    if (max_val > std.math.maxInt(T.component_type)) {
        return PgmError.IncompatibleOutputImageType;
    }
    var image = try T.init(allocator, width, height);
    errdefer image.deinit(allocator);
    const is_16bit = max_val > 255;

    for (0..height) |y| {
        for (0..width) |x| {
            var pixel: T.Pixel = undefined;
            inline for (0..pixel.len) |i| {
                var value: u16 = undefined;
                if (is_ascii) {
                    value = @intCast(try parseNextInt(reader, &buffer));
                } else {
                    if (is_16bit) {
                        const b1 = try reader.takeByte();
                        const b2 = try reader.takeByte();
                        value = (@as(u16, b1) << 8) | b2;
                    } else {
                        value = try reader.takeByte();
                    }
                }
                pixel[i] = @intCast(value);
            }
            image.setPixel(x, y, pixel);
        }
    }
    return image;
}

pub fn saveNetbpmToFilePath(image: anytype, filepath: []const u8) !void {
    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try saveNetbpmToWriter(image, &writer.interface);
}

pub fn saveNetbpmToWriter(image: anytype, writer: *std.Io.Writer) !void {
    const T = @TypeOf(image);
    const is_rgb = T.colorspace == my_lib.ColorSpace.rgb;
    const magic = if (is_rgb) "P6" else "P5";
    const max_val = std.math.maxInt(T.component_type);
    try writer.print("{s} \n{} {} \n {} \n", .{
        magic,
        image.width,
        image.height,
        max_val,
    });
    const is_16bit = max_val > 255;
    for (0..image.height) |y| {
        for (0..image.width) |x| {
            const pixel = image.getPixel(x, y);
            inline for (0..pixel.len) |i| {
                const value = pixel[i];
                if (is_16bit) {
                    try writer.writeInt(u16, value, .big);
                } else {
                    try writer.writeByte(value);
                }
            }
        }
    }
}
