const std = @import("std");
const matrix = @import("matrix.zig");
const Allocator = std.mem.Allocator;

pub const ColorSpace = enum {
    grayscale,
    rgb,
    pub fn channels(comptime self: ColorSpace) usize {
        return switch (self) {
            .grayscale => 1,
            .rgb => 3,
        };
    }
    pub fn luminance(comptime self: ColorSpace, pixel: anytype) f32 {
        std.debug.assert(self.channels() == pixel.len);
        switch (self) {
            .grayscale => return @floatFromInt(pixel[0]),
            .rgb => {
                const red: f32 = @floatFromInt(pixel[0]);
                const blue: f32 = @floatFromInt(pixel[1]);
                const green: f32 = @floatFromInt(pixel[2]);
                return 0.2126 * red + 0.7152 * blue + 0.0722 * green;
            },
        }
    }
};

pub const StorageType = enum {
    interleaved,
    planar,
};

pub fn Image(comptime color_space: ColorSpace, comptime Component: type, comptime storage: StorageType) type {
    return struct {
        const Self = @This();
        pub const colorspace = color_space;
        pub const component_type = Component;
        pub const Pixel = [color_space.channels()]Component;
        const SoAPixel = struct {
            p: Pixel,
        };
        width: usize,
        height: usize,
        data: switch (storage) {
            .interleaved => matrix.DynamicMatrix(Pixel),
            .planar => std.MultiArrayList(SoAPixel),
        },

        pub fn init(gpa: Allocator, width: usize, height: usize) !Self {
            return switch (storage) {
                .interleaved => Self{ .width = width, .height = height, .data = try matrix.DynamicMatrix(Pixel).init(gpa, width, height) },
                .planar => {
                    var data = std.MultiArrayList(SoAPixel){};
                    try data.ensureTotalCapacity(gpa, width * height);
                    data.len = width * height;
                    return Self{
                        .width = width,
                        .height = height,
                        .data = data,
                    };
                },
            };
        }

        pub fn deinit(self: Self, gpa: Allocator) void {
            switch (storage) {
                .interleaved => self.data.deinit(gpa),
                .planar => {
                    var mutable_data = self.data;
                    mutable_data.deinit(gpa);
                },
            }
        }

        pub fn convolve(self: Self, allocator: std.mem.Allocator, kernel: anytype) !Self {
            return Self{ .data = try self.data.convolve(allocator, kernel), .height = self.height, .width = self.width };
        }

        pub fn rotate180(self: *Self) void {
            self.data.rotate180();
        }

        pub fn getSliceMut(self: Self) []Pixel {
            return switch (storage) {
                .interleaved => self.data.asSliceMut(),
                .planar => @compileError("Não existe um buffer único no caso planar"),
            };
        }

        pub fn getSlice(self: Self) []const Pixel {
            return switch (storage) {
                .interleaved => self.data.asSlice(),
                .planar => @compileError("Não existe um buffer único no caso planar"),
            };
        }

        pub fn sizeInBytes(self: *Self) usize {
            return self.data.len * @sizeOf(Pixel);
        }

        pub fn getPixel(self: Self, x: usize, y: usize) Pixel {
            return switch (storage) {
                .interleaved => self.data.get(x, y),
                .planar => self.data.get(y * self.width + x).p,
            };
        }
        pub fn getLuminance(self: Self, x: usize, y: usize) f32 {
            const pixel = self.getPixel(x, y);
            return color_space.luminance(pixel);
        }

        pub fn setPixel(self: *Self, x: usize, y: usize, value: Pixel) void {
            switch (storage) {
                .interleaved => self.data.set(x, y, value),
                .planar => self.data.set(y * self.width + x, SoAPixel{ .p = value }),
            }
        }

        pub fn applyP2PTransformation(self: *Self, comptime func: anytype) void {
            if (storage == .interleaved) {
                for (self.data) |*pixel_ptr| {
                    pixel_ptr.* = func(pixel_ptr.*);
                }
            } else {
                for (0..self.height) |y| {
                    for (0..self.width) |x| {
                        self.setPixel(x, y, func(self.getPixel(x, y)));
                    }
                }
            }
        }

        pub fn getHistogram(self: *Self, allocator: Allocator) ![]usize {
            const bin_count: usize = std.math.maxInt(Self.component_type) + 1;
            var counts = try allocator.alloc(usize, bin_count);
            @memset(counts, 0);
            errdefer allocator.destroy(counts);
            for (0..self.height) |y| {
                for (0..self.width) |x| {
                    const lum = self.getLuminance(x, y);
                    counts[
                        @intFromFloat(lum)
                    ] += 1;
                }
            }
            return counts;
        }

        pub fn toGrayscale(self: Self, allocator: Allocator) !Image(.grayscale, Component, storage) {
            const DestType = Image(.grayscale, Component, storage);
            var dest = try DestType.init(allocator, self.width, self.height);
            for (0..self.height) |y| {
                for (0..self.width) |x| {
                    const lum = self.getLuminance(x, y);
                    dest.setPixel(x, y, .{@intFromFloat(lum)});
                }
            }
            return dest;
        }
    };
}

test "Image initialization and pixel access" {
    const allocator = std.testing.allocator;
    const RgbImage = Image(.rgb, u8, .interleaved);

    var img = try RgbImage.init(allocator, 10, 10);
    defer img.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 10), img.width);
    try std.testing.expectEqual(@as(usize, 10), img.height);

    const color = [_]u8{ 255, 128, 0 };
    img.setPixel(5, 5, color);
    const retrieved = img.getPixel(5, 5);

    try std.testing.expectEqual(color[0], retrieved[0]);
    try std.testing.expectEqual(color[1], retrieved[1]);
    try std.testing.expectEqual(color[2], retrieved[2]);
}

test "Grayscale image with float components" {
    const allocator = std.testing.allocator;
    const GrayImage = Image(.grayscale, f32);

    var img = try GrayImage.init(allocator, 2, 2);
    defer img.deinit(allocator);

    const val = [_]f32{0.5};
    img.setPixel(1, 1, val);
    try std.testing.expectEqual(val[0], img.getPixel(1, 1)[0]);
}
