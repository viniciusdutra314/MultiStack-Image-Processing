const std = @import("std");
pub const Netpbm = @import("formats//Netpbm.zig");
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

        width: usize,
        height: usize,
        data: switch (storage) {
            .interleaved => []Pixel,
            .planar => std.MultiArrayList(Pixel),
        },

        pub fn init(allocator: Allocator, width: usize, height: usize) !Self {
            const data = try allocator.alloc(Pixel, width * height);
            return Self{
                .width = width,
                .height = height,
                .data = data,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.data);
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
        pub fn getLuminance(self: Self, x: usize, y: usize) f32 {
            const pixel = self.getPixel(x, y);
            return color_space.luminance(pixel);
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

        pub fn get_histogram(self: *Self, allocator: Allocator) ![]usize {
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
