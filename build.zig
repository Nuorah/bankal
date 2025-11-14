const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Bundle frontend with Bun
    const bundle_frontend = b.addSystemCommand(&[_][]const u8{
        "bun",
        "build",
        "src/static/script.js",
        "--outfile=src/static/dist/bundle.min.js",
        "--minify",
        "--target=browser",
    });

    const exe = b.addExecutable(.{
        .name = "kanban",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();

    exe.step.dependOn(&bundle_frontend.step);

    b.installArtifact(exe);

    const http_common_dep = b.dependency("http_common", .{
        .target = target,
        .optimize = optimize,
    });

    const http_common_mod = http_common_dep.module("http_common");
    exe.root_module.addImport("http_common", http_common_mod);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_cmd.step);

    // Optional: separate step just for bundling
    const bundle_step = b.step("bundle", "Bundle frontend assets");
    bundle_step.dependOn(&bundle_frontend.step);
}
