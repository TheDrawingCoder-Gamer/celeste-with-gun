const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const buddy2_mod = b.addModule("buddy2", .{ .root_source_file = .{ .path = "vendor/zig-buddy2/src/buddy2.zig" } });
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const exe = b.addExecutable(.{
        .name = "cart",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("buddy2", buddy2_mod);
    exe.rdynamic = true;
    exe.entry = .disabled;
    exe.import_memory = true;
    exe.stack_size = 8192;
    exe.initial_memory = 65536 * 4;
    exe.max_memory = 65536 * 4;

    exe.export_table = true;

    // all the memory below 96kb is reserved for TIC and memory mapped I/O
    // so our own usage must start above the 96kb mark
    exe.global_base = 96 * 1024;

    b.installArtifact(exe);
}
