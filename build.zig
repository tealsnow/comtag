const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "comtag",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.linkLibC();

    const dep_config = .{
        .target = target,
        .optimize = optimize,
    };

    const vaxis = b.dependency("vaxis", dep_config);
    exe.root_module.addImport("vaxis", vaxis.module("vaxis"));

    const yazap = b.dependency("yazap", dep_config);
    exe.root_module.addImport("yazap", yazap.module("yazap"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
