const std = @import("std");
const json = std.json;
const Step = std.Build.Step;

// marks a directory and all its direct children as in the cache
const CacheDirectory = struct {
    step: Step,
    dir: std.Build.LazyPath,
    stinky_dir: std.Build.GeneratedFile,

    pub fn init(owner: *std.Build, dir: std.Build.LazyPath) *CacheDirectory {
        const self = owner.allocator.create(CacheDirectory) catch @panic("OOM");
        self.* = .{
            .step = Step.init(.{
                .owner = owner,
                .id = .custom,
                .name = "CacheDirectory",
                .makeFn = make,
            }),
            .dir = dir,
            .stinky_dir = .{ .step = &self.step },
        };
        return self;
    }

    fn getDirectory(self: *CacheDirectory) std.Build.LazyPath {
        return .{ .generated = &self.stinky_dir };
    }
    fn make(step: *Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
        const b = step.owner;
        const self = @fieldParentPtr(CacheDirectory, "step", step);
        var man = b.graph.cache.obtain();
        defer man.deinit();

        man.hash.add(@as(u32, 0x69e20ee));
        const path = self.dir.getPath(b);
        var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
        defer dir.close();
        {
            var iterator = dir.iterate();
            while (try iterator.next()) |node| {
                if (node.kind == .file) {
                    const full_paths = [_][]const u8{ path, node.name };
                    const data = try std.fs.path.join(b.allocator, &full_paths);
                    // 10 MiB
                    _ = try man.addFile(data, 1024 * 1024 * 10);
                }
            }
        }
        if (try step.cacheHit(&man)) {
            const digest = man.final();

            self.stinky_dir.path = try b.cache_root.join(b.allocator, &.{ "sprites", &digest });
            return;
        }

        const digest = man.final();
        const cache_path = "sprites" ++ std.fs.path.sep_str ++ digest;

        self.stinky_dir.path = try b.cache_root.join(b.allocator, &.{ "sprites", &digest });

        var cache_dir = b.cache_root.handle.makeOpenPath(cache_path, .{}) catch |err| {
            return step.fail("unable to make path '{}{s}': {s}", .{
                b.cache_root, cache_path, @errorName(err),
            });
        };
        defer cache_dir.close();

        {
            var iterator = dir.iterate();
            while (try iterator.next()) |node| {
                if (node.kind == .file) {
                    const src_path = try std.fs.path.join(b.allocator, &.{ path, node.name });
                    const dst_path = try b.cache_root.join(b.allocator, &.{ "sprites", &digest, node.name });
                    try std.fs.copyFileAbsolute(src_path, dst_path, .{});
                }
            }
        }

        try step.writeManifest(&man);
    }
};
pub fn build(b: *std.Build) !void {
    const optimize = std.builtin.OptimizeMode.ReleaseSmall;
    const optimize_native = std.builtin.OptimizeMode.Debug;
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const native_target = b.resolveTargetQuery(.{});
    const test_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const buddy2_runtime_dep = b.dependency("buddy2", .{
        .target = target,
        .optimize = optimize,
    });
    const buddy2_test_dep = b.dependency("buddy2", .{
        .target = test_target,
    });
    const s2s_runtime_dep = b.dependency("s2s", .{ .target = target, .optimize = optimize });
    const s2s_test_dep = b.dependency("s2s", .{ .target = test_target, .optimize = optimize_native });
    const s2s_native_dep = b.dependency("s2s", .{ .target = native_target, .optimize = optimize_native });
    const tatl_dep = b.dependency("tatl", .{});
    const common_mod = b.addModule("common", .{ .root_source_file = .{ .path = "common/lib.zig" } });
    const exe = b.addExecutable(.{
        .name = "cart",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("buddy2", buddy2_runtime_dep.module("buddy2"));
    exe.root_module.addImport("s2s", s2s_runtime_dep.module("s2s"));
    exe.root_module.addImport("common", common_mod);
    tic80ify_wasm(exe);

    b.installArtifact(exe);

    const converter = b.addExecutable(.{ .name = "converter", .root_source_file = .{ .path = "converter/main.zig" }, .target = native_target, .optimize = optimize_native });

    converter.root_module.addImport("s2s", s2s_native_dep.module("s2s"));
    converter.root_module.addImport("common", common_mod);
    converter.root_module.addImport("tatl", tatl_dep.module("tatl"));
    const cached_dir = CacheDirectory.init(b, .{ .path = "assets/sprites" });

    const pack_files = b.addRunArtifact(converter);
    pack_files.step.dependOn(&cached_dir.step);
    pack_files.addArg("pack");
    const packed_file = pack_files.addOutputFileArg("res.wasmp");
    pack_files.addFileArg(.{ .path = "assets/unpacked_data.wasmp" });
    pack_files.addFileArg(.{ .path = "assets/palette.hex" });
    pack_files.addDirectoryArg(cached_dir.getDirectory());
    pack_files.addFileArg(.{ .path = "assets/sprites.txt" });
    pack_files.addFileArg(.{ .path = "assets/tiles.aseprite" });
    pack_files.addFileArg(.{ .path = "assets/maps/map.ldtk" });

    const installed_packed_file = b.addInstallBinFile(packed_file, "res.wasmp");
    installed_packed_file.step.dependOn(&pack_files.step);

    const unpack_file = b.addRunArtifact(converter);
    unpack_file.addArg("unpack");
    unpack_file.addArg(b.getInstallPath(installed_packed_file.dir, "res.wasmp"));
    unpack_file.addFileArg(.{ .path = "assets/unpacked_data.wasmp" });

    const test_step = b.step("test", "Run build tests");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = test_target,
        .name = "test",
    });
    tests.root_module.addImport("buddy2", buddy2_test_dep.module("buddy2"));
    tests.root_module.addImport("common", common_mod);
    tests.root_module.addImport("s2s", s2s_test_dep.module("s2s"));
    const common_tests = b.addTest(.{
        .root_source_file = .{ .path = "common/lib.zig" },
        .target = native_target,
        .name = "common_test",
    });

    const run_tests = b.addRunArtifact(tests);
    const run_common_tests = b.addRunArtifact(common_tests);
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_common_tests.step);

    const unpack_data_step = b.step("unpack_data", "Update assets/unpacked_data.wasmp to use latest data from output file");
    unpack_data_step.dependOn(&unpack_file.step);

    b.getInstallStep().dependOn(&installed_packed_file.step);
}

fn tic80ify_wasm(s: *std.Build.Step.Compile) void {
    s.rdynamic = true;
    s.entry = .disabled;
    s.import_memory = true;
    s.stack_size = 8192;
    s.initial_memory = 65536 * 4;
    s.max_memory = 65536 * 4;

    s.export_table = true;

    // all the memory below 96kb is reserved for TIC and memory mapped I/O
    // so our own usage must start above the 96kb mark
    s.global_base = 96 * 1024;
}
