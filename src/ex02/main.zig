const std = @import("std");
const my_lib = @import("ImageProcessing");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var img = try my_lib.Netpbm.readPgmFromFilePathAs(my_lib.Image(.grayscale, u8, .interleaved), allocator, "a.pgm");
    defer img.deinit();
    std.debug.print("height={} width={} \n", .{ img.height, img.width });
    std.debug.print("size in memory {} KB\n", .{img.sizeInBytes() / (1024)});
}
