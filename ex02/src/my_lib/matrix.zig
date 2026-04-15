const std = @import("std");

fn MatrixImplementation(comptime T: type, comptime W_opt: ?usize, comptime H_opt: ?usize) type {
    const is_static = (W_opt != null) and (H_opt != null);
    const W = W_opt orelse 0;
    const H = H_opt orelse 0;
    return struct {
        const Self = @This();
        _width: usize = if (is_static) W else 0,
        _height: usize = if (is_static) H else 0,
        _storage: if (is_static) [H * W]T else []T,
        pub fn init(gpa: std.mem.Allocator, width: usize, height: usize) !Self {
            if (is_static) {
                @compileError("Static matrix cannot be initialized with dynamic size");
            }
            return Self{ ._width = width, ._height = height, ._storage = try gpa.alloc(T, try std.math.mul(usize, width, height)) };
        }
        pub fn initStaticFill(value: T) Self {
            if (!is_static) {
                @compileError("Static matrix cannot be initialized with dynamic size");
            }
            return .{ ._storage = [_]T{value} ** (H * W) };
        }

        pub fn deinit(self: Self, gpa: std.mem.Allocator) void {
            if (is_static) {
                @compileError("Static matrix cannot be deinitialized");
            }
            gpa.free(self._storage);
        }

        pub fn get_width(self: Self) usize {
            return self._width;
        }

        pub fn get_height(self: Self) usize {
            return self._height;
        }
        pub fn len(self: Self) usize {
            return self._height * self._width;
        }

        pub fn rotate180(self: *Self) void {
            var i: usize = 0;
            var j: usize = self.len() - 1;

            while (i < j) : ({
                i += 1;
                j -= 1;
            }) {
                const tmp = self._storage[i];
                self._storage[i] = self._storage[j];
                self._storage[j] = tmp;
            }
        }

        pub fn convolve(self: *const Self, allocator: std.mem.Allocator, kernel: anytype) !Self {
            if (is_static) @compileError("convolve currently implemented for dynamic matrices");

            var dst = try Self.init(allocator, self._width, self._height);
            errdefer dst.deinit(allocator);

            const kw: usize = kernel.get_width();
            const kh: usize = kernel.get_height();
            std.debug.assert(kw > 0 and kh > 0);

            const kcx: isize = @intCast(kw / 2);
            const kcy: isize = @intCast(kh / 2);

            const tinfo = @typeInfo(T);

            for (0..self._height) |y| {
                for (0..self._width) |x| {
                    switch (tinfo) {
                        .array => |arr| {
                            // Pixel path: T = [N]C
                            const N = arr.len;
                            const C = arr.child;

                            var out: T = undefined;

                            inline for (0..N) |ch| {
                                var acc: f32 = 0.0;

                                for (0..kh) |ky| {
                                    for (0..kw) |kx| {
                                        const sx: isize = @as(isize, @intCast(x)) + @as(isize, @intCast(kx)) - kcx;
                                        const sy: isize = @as(isize, @intCast(y)) + @as(isize, @intCast(ky)) - kcy;

                                        if (sx < 0 or sy < 0 or sx >= @as(isize, @intCast(self._width)) or sy >= @as(isize, @intCast(self._height))) {
                                            continue; // zero padding
                                        }

                                        const p = self.get(@intCast(sx), @intCast(sy));
                                        const sample: f32 = switch (@typeInfo(C)) {
                                            .float => @as(f32, @floatCast(p[ch])),
                                            .int, .comptime_int => @floatFromInt(p[ch]),
                                            else => @compileError("Pixel component must be int or float"),
                                        };
                                        const kval: f32 = @as(f32, @floatCast(kernel.get(kx, ky)));
                                        acc += sample * kval;
                                    }
                                }

                                out[ch] = switch (@typeInfo(C)) {
                                    .float => @as(C, @floatCast(acc)),
                                    .int, .comptime_int => blk: {
                                        const lo: f32 = @floatFromInt(std.math.minInt(C));
                                        const hi: f32 = @floatFromInt(std.math.maxInt(C));
                                        const clamped = @max(lo, @min(hi, acc));
                                        break :blk @as(C, @intFromFloat(clamped));
                                    },
                                    else => @compileError("Pixel component must be int or float"),
                                };
                            }

                            dst.set(x, y, out);
                        },
                        .float => {
                            var acc: f32 = 0.0;
                            for (0..kh) |ky| {
                                for (0..kw) |kx| {
                                    const sx: isize = @as(isize, @intCast(x)) + @as(isize, @intCast(kx)) - kcx;
                                    const sy: isize = @as(isize, @intCast(y)) + @as(isize, @intCast(ky)) - kcy;
                                    if (sx < 0 or sy < 0 or sx >= @as(isize, @intCast(self._width)) or sy >= @as(isize, @intCast(self._height))) continue;
                                    const sample: f32 = @as(f32, @floatCast(self.get(@intCast(sx), @intCast(sy))));
                                    const kval: f32 = @as(f32, @floatCast(kernel.get(kx, ky)));
                                    acc += sample * kval;
                                }
                            }
                            dst.set(x, y, @as(T, @floatCast(acc)));
                        },
                        .int, .comptime_int => {
                            var acc: f32 = 0.0;
                            for (0..kh) |ky| {
                                for (0..kw) |kx| {
                                    const sx: isize = @as(isize, @intCast(x)) + @as(isize, @intCast(kx)) - kcx;
                                    const sy: isize = @as(isize, @intCast(y)) + @as(isize, @intCast(ky)) - kcy;
                                    if (sx < 0 or sy < 0 or sx >= @as(isize, @intCast(self._width)) or sy >= @as(isize, @intCast(self._height))) continue;
                                    const sample: f32 = @floatFromInt(self.get(@intCast(sx), @intCast(sy)));
                                    const kval: f32 = @as(f32, @floatCast(kernel.get(kx, ky)));
                                    acc += sample * kval;
                                }
                            }
                            const lo: f32 = @floatFromInt(std.math.minInt(T));
                            const hi: f32 = @floatFromInt(std.math.maxInt(T));
                            const clamped = @max(lo, @min(hi, acc));
                            dst.set(x, y, @as(T, @intFromFloat(clamped)));
                        },
                        else => @compileError("convolve supports scalar int/float or fixed-size array pixels"),
                    }
                }
            }

            return dst;
        }

        pub fn initFromRows(rows: [H][W]T) Self {
            var result = Self.initStaticFill(std.mem.zeroes(T));

            for (0..H) |y| {
                for (0..W) |x| {
                    result.set(x, y, rows[y][x]);
                }
            }
            return result;
        }

        pub fn asSliceMut(self: Self) []T {
            return if (is_static) self._storage[0..] else self._storage;
        }

        pub fn asSlice(self: *const Self) []const T {
            return if (is_static) self._storage[0..] else self._storage;
        }

        fn index(self: Self, x: usize, y: usize) usize {
            std.debug.assert(x < self._width);
            std.debug.assert(y < self._height);
            return y * self._width + x;
        }
        pub fn get(self: Self, x: usize, y: usize) T {
            return self._storage[self.index(x, y)];
        }
        pub fn set(self: *Self, x: usize, y: usize, element: T) void {
            self._storage[self.index(x, y)] = element;
        }
    };
}

pub fn DynamicMatrix(comptime T: type) type {
    return MatrixImplementation(T, null, null);
}

pub fn StaticMatrix(comptime T: type, comptime W: usize, comptime H: usize) type {
    return MatrixImplementation(T, W, H);
}

test "dynamic + static wrappers" {
    var matrix = StaticMatrix(f32, 3, 3).initStaticFill(0.0);
    matrix.set(1, 1, 5);
    try std.testing.expect(matrix.get(1, 1) == 5);
    try std.testing.expect(matrix.get(0, 0) == 0.0);
    try std.testing.expect(matrix._height == 3);
    try std.testing.expect(matrix._width == 3);
    var num_zeros: usize = 0;
    for (matrix.asSlice()) |elem| {
        if (elem == 0.0) {
            num_zeros += 1;
        }
    }
    try std.testing.expect(num_zeros == 8);
}
