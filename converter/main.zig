const std = @import("std");
const s2s = @import("s2s");
const SavedLevel = @import("common").Level;
const math = @import("common").math;
const json = std.json;
const parsec = @import("parsec");

const RawFieldInstance = struct { __identifier: []u8, __value: json.Value, __type: []u8 };
const EntityInstance = struct { __identifier: []u8, __grid: [2]i32, fieldInstances: []RawFieldInstance, __worldX: i32, __worldY: i32, width: u31, height: u31 };
const AutoLayerTile = struct { px: [2]u31, t: u32 };
const LayerInstance = struct { __type: []u8, __identifier: []u8, entityInstances: []EntityInstance, autoLayerTiles: []AutoLayerTile };
const Level = struct { worldX: i32, worldY: i32, pxWid: u31, pxHei: u31, cammode: u8, death_bottom: bool, layerInstances: []LayerInstance };
const PointType = struct { cx: i32, cy: i32 };

var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
var alloc: std.mem.Allocator = undefined;
pub fn main() !void {
    alloc = gpa.allocator();
    var args = try std.process.argsWithAllocator(alloc);
    if (!args.skip()) return error.TooFewArgs;

    const inpath = args.next() orelse return error.TooFewArgs;
    const mappath = args.next() orelse return error.TooFewArgs;

    const mapfile = try std.fs.openFileAbsolute(mappath, .{ .mode = .read_only });

    const in_map_data = try mapfile.readToEndAlloc(alloc, 1024 * 1024);
    const map_data = try get_compressed_map(in_map_data);

    var da_map: [32_640]u8 = .{0} ** 32_640;

    for (map_data.tiles) |tile| {
        da_map[@intCast(tile.pos.y * 240 + tile.pos.x)] = tile.tile;
    }

    var infile = try std.fs.openFileAbsolute(inpath, .{ .mode = .read_write });
    defer infile.close();
    const stripped_maps = try strip_maps(&infile);
    try infile.seekTo(0);
    try infile.writeAll(stripped_maps);
    try save_bin_section(infile.writer(), "MAP", &da_map, 240, true);

    @memset(@as([]u8, &da_map), 0);

    var map_data_fbs = std.io.fixedBufferStream(&da_map);
    try s2s.serialize(map_data_fbs.writer(), []SavedLevel, map_data.levels);
    try save_bin_section(infile.writer(), "MAP7", &da_map, 240, true);
}

fn buf_empty(data: []const u8) bool {
    for (data) |i| {
        if (i != 0)
            return false;
    }
    return true;
}

fn buf2str(writer: anytype, data: []const u8, flip: bool) !void {
    for (data) |i| {
        var buf: [2]u8 = undefined;
        _ = try std.fmt.bufPrint(&buf, "{x:0>2}", .{i});
        if (flip) {
            std.mem.swap(u8, &buf[0], &buf[1]);
        }
        try writer.print("{s}", .{&buf});
    }
}
fn save_bin_buffer(writer: anytype, data: []const u8, row: usize, flip: bool) !void {
    if (buf_empty(data)) return;
    try writer.print("-- {:0>3}:", .{row});
    try buf2str(writer, data, flip);
    _ = try writer.write("\n");
}

fn save_bin_section(writer: anytype, tag: []const u8, data: []const u8, row_size: usize, flip: bool) !void {
    const count = @divExact(data.len, row_size);

    if (buf_empty(data)) return;
    try writer.print("-- <{s}>\n", .{tag});

    {
        var row: usize = 0;
        while (row < count) : (row += 1) {
            const offset = row_size * row;
            try save_bin_buffer(writer, data[offset .. offset + row_size], row, flip);
        }
    }

    try writer.print("-- </{s}>\n\n", .{tag});
}

fn get_compressed_map(map: []u8) !SavedLevel.CompressedMap {
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

    return compressed_map;
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
    } else if (std.mem.eql(u8, entity.__identifier, "Checkpoint")) {
        kind = .checkpoint;
    }

    if (kind) |k| {
        try o_entities.append(.{ .x = ex, .y = ey, .w = ew, .h = eh, .kind = k });
    }
}

fn strip_maps(input: *std.fs.File) ![]u8 {
    const FBS = std.fs.File;
    const map_lit = parsec.Literal(FBS).init("-- <MAP>").parser();
    const map_end_lit = parsec.Literal(FBS).init("-- </MAP>").parser();
    const map7_lit = parsec.Literal(FBS).init("-- <MAP7>").parser();
    const map7_end_lit = parsec.Literal(FBS).init("-- </MAP7>").parser();
    const ManyTilLit = parsec.ManyTill(u8, []u8, FBS);
    const many_til_map = ManyTilLit.init(parsec.AnyChar(FBS).parser(), map_lit).parser();
    const skip_map_end = ManyTilLit.init(parsec.AnyChar(FBS).parser(), map_end_lit).parser();
    const many_til_map7 = ManyTilLit.init(parsec.AnyChar(FBS).parser(), map7_lit).parser();
    const skip_map7_end = ManyTilLit.init(parsec.AnyChar(FBS).parser(), map7_end_lit).parser();

    const final = parsec.Sequence(struct { []u8, []u8, []u8, []u8 }, FBS).init(.{ many_til_map, skip_map_end, many_til_map7, skip_map7_end });

    const res = try final.parser().parseOrDie(alloc, input);
    defer res.deinit();
    const rest = try input.reader().readAllAlloc(alloc, 65565);
    defer alloc.free(rest);
    const out = try std.mem.join(alloc, "", &.{ res.value[0], res.value[2], rest });

    return out;
}
