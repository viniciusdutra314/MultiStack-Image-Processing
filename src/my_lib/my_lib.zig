const std = @import("std");
pub const Netpbm = @import("formats//Netpbm.zig");
const Allocator = std.mem.Allocator;

pub const ColorSpace = enum {
    grayscale,
    rgb,
    rgba,
    pub fn channels(self: ColorSpace) usize {
        return switch (self) {
            .grayscale => 1,
            .rgb => 3,
            .rgba => 4,
        };
    }
};

pub const StorageType = enum {
    interleaved,
    planar,
};

pub const ConversionPolicy = enum {
    strict,
    scale,
};

pub fn Image(comptime color_space: ColorSpace, comptime Component: type, comptime storage: StorageType) type {
    const Pixel = [color_space.channels()]Component;
    return struct {
        const Self = @This();
        pub const colorspace = color_space;
        pub const component_type = Component;

        width: usize,
        height: usize,
        data: switch (storage) {
            .interleaved => []Pixel,
            .planar => std.MultiArrayList(Pixel),
        },
        allocator: Allocator,

        pub fn init(allocator: Allocator, width: usize, height: usize) !Self {
            const data = try allocator.alloc(Pixel, width * height);
            return Self{
                .width = width,
                .height = height,
                .data = data,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        pub fn sizeInBytes(self: *Self) usize {
            return self.data.len * @sizeOf(Pixel);
        }

        pub fn getPixel(self: Self, x: usize, y: usize) Pixel {
            std.debug.assert(x < self.width);
            std.debug.assert(y < self.height);
            const index = y * self.width + x;
            return switch (storage) {
                .interleaved => self.data[index],
                .planar => self.data.get(index),
            };
        }

        pub fn setPixel(self: *Self, x: usize, y: usize, value: Pixel) void {
            std.debug.assert(x < self.width);
            std.debug.assert(y < self.height);
            const index = y * self.width + x;
            switch (storage) {
                .interleaved => self.data[index] = value,
                .planar => self.data.set(index, value),
            }
        }
        // pub fn get_histogram(self: *Self,allocator:, bin_count_opt: ?usize) ![]usize {
        //     const bin_count: usize = undefined;
        //     if (bin_count_opt) |count| {
        //         bin_count = count;
        //     } else {
        //         bin_count = 256;
        //     }
        // }
    };
}

test "Image initialization and pixel access" {
    const allocator = std.testing.allocator;
    const RgbImage = Image(.rgb, u8, .interleaved);

    var img = try RgbImage.init(allocator, 10, 10);
    defer img.deinit();

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
    defer img.deinit();

    const val = [_]f32{0.5};
    img.setPixel(1, 1, val);
    try std.testing.expectEqual(val[0], img.getPixel(1, 1)[0]);
}
