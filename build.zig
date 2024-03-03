const std = @import("std");
const json = std.json;

const SavedLevel = @import("common/Level.zig");
const math = @import("common/math.zig");
const s2s = @import("vendor/s2s/s2s.zig");
const wasmp_parser = @import("wasmp_parser/main.zig");

const map = @embedFile("assets/maps/map.ldtk");
const wasmp = @embedFile("fun.wasmp");
var buf: [65565 * 4]u8 = undefined;
const GPA = std.heap.GeneralPurposeAllocator(.{});
var gpa: GPA = undefined;
var alloc: std.mem.Allocator = undefined;

const RawFieldInstance = struct { __identifier: []u8, __value: json.Value, __type: []u8 };
const EntityInstance = struct { __identifier: []u8, __grid: [2]i32, fieldInstances: []RawFieldInstance, __worldX: i32, __worldY: i32, width: u31, height: u31 };
const AutoLayerTile = struct { px: [2]u31, t: u32 };
const LayerInstance = struct { __type: []u8, __identifier: []u8, entityInstances: []EntityInstance, autoLayerTiles: []AutoLayerTile };
const Level = struct { worldX: i32, worldY: i32, pxWid: u31, pxHei: u31, cammode: u8, death_bottom: bool, layerInstances: []LayerInstance };

const PointType = struct { cx: i32, cy: i32 };
fn save_map(b: *std.Build) ![]const u8 {
    const tmp = b.makeTempPath();
    var tmp_dir = try std.fs.openDirAbsolute(tmp, .{});
    defer tmp_dir.close();

    const out_str = try get_compressed_map();

    var file = try tmp_dir.createFile("map.bin", .{});
    defer file.close();
    try file.writeAll(out_str);
    return std.fs.path.join(alloc, &[_][]const u8{ tmp, "map.bin" });
}
pub fn build(b: *std.Build) !void {
    gpa = GPA{};
    alloc = gpa.allocator();

    const optimize = b.standardOptimizeOption(.{});
    const map_file = try save_map(b);
    const funny = try wasmp_parser.strip_maps(alloc, wasmp);
    std.debug.print("{s}", .{funny});
    const buddy2_mod = b.addModule("buddy2", .{ .root_source_file = .{ .path = "vendor/zig-buddy2/src/buddy2.zig" } });
    const s2s_mod = b.addModule("s2s", .{ .root_source_file = .{ .path = "vendor/s2s/s2s.zig" } });
    const common_mod = b.addModule("common", .{ .root_source_file = .{ .path = "common/lib.zig" } });
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const test_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const exe = b.addExecutable(.{
        .name = "cart",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("buddy2", buddy2_mod);
    exe.root_module.addImport("s2s", s2s_mod);
    exe.root_module.addImport("common", common_mod);
    tic80ify_wasm(exe);

    b.installArtifact(exe);
    const converter = b.addExecutable(.{ .name = "converter", .root_source_file = .{ .path = "converter/main.zig" }, .target = target, .optimize = optimize });

    converter.root_module.addImport("buddy2", buddy2_mod);
    converter.root_module.addImport("s2s", s2s_mod);
    converter.root_module.addImport("common", common_mod);
    converter.root_module.addAnonymousImport("map", .{ .root_source_file = .{ .path = map_file } });
    tic80ify_wasm(converter);

    b.installArtifact(converter);

    const test_step = b.step("test", "Run build tests");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = test_target,
        .name = "test",
    });
    tests.root_module.addImport("buddy2", buddy2_mod);

    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
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

fn get_compressed_map() ![]const u8 {
    const val = try json.parseFromSliceLeaky(json.Value, alloc, map, .{});
    var v = val.object;
    const keys = v.keys();
    for (keys) |k| {
        if (!std.mem.eql(u8, k, "levels")) {
            _ = try v.put(k, json.Value.null);
        }
    }
    const levels = v.getPtr("levels") orelse return error.MissingField;
    for (levels.array.items) |*level| {
        var cam_mode: SavedLevel.CamMode = .locked;
        var death_bottom = true;
        for ((level.object.get("fieldInstances") orelse return error.MissingField).array.items) |field| {
            const raw_field = try json.parseFromValueLeaky(RawFieldInstance, alloc, field, .{ .ignore_unknown_fields = true });
            if (std.mem.eql(u8, raw_field.__identifier, "CameraType")) {
                const field_v = raw_field.__value.string;
                if (std.mem.eql(u8, field_v, "Locked")) {
                    cam_mode = .locked;
                } else if (std.mem.eql(u8, field_v, "FollowX")) {
                    cam_mode = .follow_x;
                } else if (std.mem.eql(u8, field_v, "FollowY")) {
                    cam_mode = .follow_y;
                } else if (std.mem.eql(u8, field_v, "FreeFollow")) {
                    cam_mode = .free_follow;
                }
            } else if (std.mem.eql(u8, raw_field.__identifier, "DeathBottom")) {
                death_bottom = raw_field.__value.bool;
            }
        }
        try level.object.put("cammode", json.Value{ .integer = @intFromEnum(cam_mode) });
        try level.object.put("death_bottom", json.Value{ .bool = death_bottom });
        try level.object.put("fieldInstances", json.Value.null);
    }
    const good_levels = try json.parseFromValueLeaky([]Level, alloc, levels.*, .{ .ignore_unknown_fields = true });
    var tiles = std.ArrayList(SavedLevel.Tile).init(alloc);
    var out_levels = std.ArrayList(SavedLevel).init(alloc);
    for (good_levels) |good| {
        try process_level(&tiles, &out_levels, good);
    }
    const compressed_map = SavedLevel.CompressedMap{ .levels = out_levels.items, .tiles = tiles.items };

    // if it can't fit inside two maps i prob did something wrong
    var stream_buf: std.ArrayList(u8) = std.ArrayList(u8).init(alloc);
    const writer = stream_buf.writer();
    try s2s.serialize(writer, SavedLevel.CompressedMap, compressed_map);
    // if greater than 64 KiB
    if (stream_buf.items.len > 65665) {
        return error.MapTooLarge;
    }
    // std.debug.print("{s}", .{res});
    return stream_buf.items;
}

fn process_level(o_tiles: *std.ArrayList(SavedLevel.Tile), o_levels: *std.ArrayList(SavedLevel), level: Level) !void {
    const tile_x = @divFloor(level.worldX, 8);
    const tile_y = @divFloor(level.worldY, 8);
    const tile_w = @divFloor(level.pxWid, 8);
    const tile_h = @divFloor(level.pxHei, 8);
    const pix_x = level.worldX;
    const pix_y = level.worldY;

    var entities = std.ArrayList(SavedLevel.Entity).init(alloc);
    for (level.layerInstances) |layer| {
        if (std.mem.eql(u8, layer.__identifier, "TileMap")) {
            for (layer.autoLayerTiles) |auto_tile| {
                const tx = @divFloor(auto_tile.px[0], 8);
                const ty = @divFloor(auto_tile.px[1], 8);
                try o_tiles.append(.{ .pos = .{ .x = tile_x + tx, .y = tile_y + ty }, .tile = @intCast(auto_tile.t) });
            }
        } else if (std.mem.eql(u8, layer.__identifier, "Entities")) {
            for (layer.entityInstances) |entity| {
                try process_entity(.{ .x = pix_x, .y = pix_y }, &entities, entity);
            }
        } else {
            return error.UnknownLayer;
        }
    }
    try o_levels.append(.{ .x = tile_x, .y = tile_y, .width = tile_w, .height = tile_h, .entities = entities.items, .cam_mode = @enumFromInt(level.cammode), .death_bottom = level.death_bottom });
}

fn process_entity(world_pos: math.Point, o_entities: *std.ArrayList(SavedLevel.Entity), entity: EntityInstance) !void {
    const ex = entity.__worldX;
    const ey = entity.__worldY;
    const ew = entity.width;
    const eh = entity.height;
    var kind: ?SavedLevel.Entity.Kind = null;
    if (std.mem.eql(u8, entity.__identifier, "Crumble")) {
        kind = .crumble;
    } else if (std.mem.eql(u8, entity.__identifier, "PlayerStart")) {
        var world_start = false;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "WorldStart")) {
                world_start = field.__value.bool;
                break;
            }
        }
        kind = .{ .player_start = world_start };
    } else if (std.mem.eql(u8, entity.__identifier, "Destructible")) {
        var shoot_only = false;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "shoot_only")) {
                shoot_only = field.__value.bool;
                break;
            }
        }
        kind = .{ .destructible = .{ .shoot_only = shoot_only } };
    } else if (std.mem.eql(u8, entity.__identifier, "Switch")) {
        var can_shoot = false;
        var can_touch = true;
        var s_kind: u8 = 0;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "kind")) {
                s_kind = @intCast(field.__value.integer);
            } else if (std.mem.eql(u8, field.__identifier, "can_shoot")) {
                can_shoot = field.__value.bool;
            } else if (std.mem.eql(u8, field.__identifier, "can_touch")) {
                can_touch = field.__value.bool;
            }
        }
        kind = .{ .switch_coin = .{ .kind = s_kind, .shootable = can_shoot, .touchable = can_touch } };
    } else if (std.mem.eql(u8, entity.__identifier, "SwitchDoor")) {
        var s_kind: u8 = 0;
        var target: PointType = .{ .cx = 0, .cy = 0 };
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "kind")) {
                s_kind = @intCast(field.__value.integer);
            } else if (std.mem.eql(u8, field.__identifier, "target")) {
                const res = try json.parseFromValue(PointType, alloc, field.__value, .{});
                defer res.deinit();
                target = res.value;
            }
        }
        kind = .{ .switch_door = .{ .kind = s_kind, .target = .{ .x = world_pos.x + target.cx * 8, .y = world_pos.y + target.cy * 8 } } };
    } else if (std.mem.eql(u8, entity.__identifier, "TrafficBlock")) {
        var target: PointType = .{ .cx = 0, .cy = 0 };
        var speed: f32 = 1.0;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "target")) {
                const res = try json.parseFromValue(PointType, alloc, field.__value, .{});
                defer res.deinit();
                target = res.value;
            } else if (std.mem.eql(u8, field.__identifier, "Speed")) {
                const res = try json.parseFromValue(f32, alloc, field.__value, .{});
                defer res.deinit();
                speed = res.value;
            }
        }
        kind = .{ .traffic_block = .{ .target = .{ .x = world_pos.x + target.cx * 8, .y = world_pos.y + target.cy * 8 }, .speed = speed } };
    } else if (std.mem.eql(u8, entity.__identifier, "Spike")) {
        var dir: math.CardinalDir = .up;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "Direction")) {
                const v = field.__value.string;
                if (std.mem.eql(u8, v, "Left")) {
                    dir = .left;
                } else if (std.mem.eql(u8, v, "Up")) {
                    dir = .up;
                } else if (std.mem.eql(u8, v, "Right")) {
                    dir = .right;
                } else if (std.mem.eql(u8, v, "Down")) {
                    dir = .down;
                }
            }
        }
        kind = .{ .spike = .{ .direction = dir } };
    } else if (std.mem.eql(u8, entity.__identifier, "DashCrystal")) {
        var dashes: u8 = 1;
        for (entity.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "Dashes")) {
                dashes = @intCast(field.__value.integer);
            }
        }
        kind = .{ .dash_crystal = dashes };
    }

    if (kind) |k| {
        try o_entities.append(.{ .x = ex, .y = ey, .w = ew, .h = eh, .kind = k });
    }
}
