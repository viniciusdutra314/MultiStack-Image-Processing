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

pub fn readPgmFromFilePathAs(comptime T: type, allocator: std.mem.Allocator, filepath: []const u8) !T {
    const file = try std.fs.cwd().openFile(filepath, .{});
    var buffer: [1024]u8 = undefined;
    var reader_file = file.reader(&buffer);
    return try readPgmFromReaderAs(T, allocator, &reader_file.interface);
}

pub fn readPgmFromReaderAs(
    comptime T: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) !T {
    if (T.colorspace != my_lib.ColorSpace.grayscale) {
        return PgmError.IncompatibleOutputImageType;
    }

    var buffer: [64]u8 = undefined;
    const magic = try readNextToken(reader, &buffer);
    const is_p2 = std.mem.eql(u8, magic, "P2");
    const is_p5 = std.mem.eql(u8, magic, "P5");
    if (!is_p5 and !is_p2) {
        return PgmError.InvalidMagicNumber;
    }
    const width = try parseNextInt(reader, &buffer);
    const height = try parseNextInt(reader, &buffer);
    const max_val = try parseNextInt(reader, &buffer);
    if (max_val > std.math.maxInt(T.component_type)) {
        return PgmError.IncompatibleOutputImageType;
    }
    var image = try T.init(allocator, width, height);
    errdefer image.deinit(allocator);
    if (is_p2) {
        for (0..height) |y| {
            for (0..width) |x| {
                const val = try parseNextInt(reader, &buffer);
                image.setPixel(x, y, .{@as(T.component_type, @intCast(val))});
            }
        }
    } else {
        const is_16bit = max_val > 255;
        for (0..height) |y| {
            for (0..width) |x| {
                var value: u16 = undefined;
                if (is_16bit) {
                    const b1 = try reader.takeByte();
                    const b2 = try reader.takeByte();
                    value = (@as(u16, b1) << 8) | b2;
                } else {
                    value = try reader.takeByte();
                }
                image.setPixel(x, y, .{@as(T.component_type, @intCast(value))});
            }
        }
    }

    return image;
}
