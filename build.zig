const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Install frontend deps
    const bun_install = b.addSystemCommand(&[_][]const u8{
        "bun",
        "install",
    });
    bun_install.setCwd(b.path("src/static"));

    // Bundle frontend with Bun
    const bundle_frontend = b.addSystemCommand(&[_][]const u8{
        "bun",
        "build",
        "src/static/script.js",
        "--outfile=src/static/dist/bundle.min.js",
        "--minify",
        "--target=browser",
    });
    bundle_frontend.step.dependOn(&bun_install.step);

    const exe = b.addExecutable(.{
        .name = "bankal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
    exe.step.dependOn(&bundle_frontend.step);

    b.installArtifact(exe);

    const http_common_mod = b.addModule("http_common", .{
        .root_source_file = b.path("src/vendor/http_common/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("http_common", http_common_mod);

    const event_wal_mod = b.addModule("event_wal", .{
        .root_source_file = b.path("src/vendor/event_wal/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("event_wal", event_wal_mod);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_cmd.step);

    const bundle_step = b.step("bundle", "Install deps and bundle frontend");
    bundle_step.dependOn(&bundle_frontend.step);
}
