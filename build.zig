const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const my_lib_mod = b.addModule("ImageProcessing", .{
        .root_source_file = b.path("src/my_lib/my_lib.zig"),
        .target = target,
    });

    var dir = std.fs.cwd().openDir("src/", .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory and std.mem.startsWith(u8, entry.name, "ex")) {
            const path = b.fmt("src/{s}/main.zig", .{entry.name});
            const exe = b.addExecutable(.{
                .name = entry.name,
                .root_module = b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "ImageProcessing", .module = my_lib_mod },
                    },
                }),
            });

            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_desc = b.fmt("Run {s}", .{entry.name});
            const run_step = b.step(entry.name, run_desc);
            run_step.dependOn(&run_cmd.step);
        }
    }
}
