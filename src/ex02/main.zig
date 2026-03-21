const std = @import("std");
const my_lib = @import("ImageProcessing");

fn brigthen(p: [3]u8) [3]u8 {
    return .{ p[0] -| 200, p[1] -| 200, p[2] -| 200 };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var img = try my_lib.Netpbm.readNetbpmFromFilePathAs(my_lib.Image(.rgb, u8, .planar), allocator, "billie.ppm");
    defer img.deinit(allocator);

    std.debug.print("height={} width={} \n", .{ img.height, img.width });
    std.debug.print("size in memory {} KB\n", .{img.sizeInBytes() / (1024)});
    img.applyP2PTransformation(brigthen);
    try my_lib.Netpbm.saveNetbpmToFilePath(img, "inverted_billie.ppm");
}
