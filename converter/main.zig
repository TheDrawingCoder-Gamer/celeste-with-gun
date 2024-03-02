const tic = @import("common").tic;
const Buddy2Allocator = @import("buddy2").Buddy2Allocator(.{});
const s2s = @import("s2s");
const std = @import("std");
const json = std.json;
const SavedLevel = @import("common").Level;
const math = @import("common").math;

var buf: [1024 * 40]u8 = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

// WEEWOO! THIS IS REALLY BEEG!
const file = @embedFile("map.ldtk");

const RawFieldInstance = struct { __identifier: []u8, __value: json.Value, __type: []u8 };
const EntityInstance = struct { __identifier: []u8, __grid: [2]i32, fieldInstances: []RawFieldInstance, __worldX: i32, __worldY: i32, width: u31, height: u31 };
const AutoLayerTile = struct { px: [2]u31, t: u32 };
const LayerInstance = struct { __type: []u8, __identifier: []u8, entityInstances: []EntityInstance, autoLayerTiles: []AutoLayerTile };
const Level = struct { worldX: i32, worldY: i32, pxWid: u31, pxHei: u31, fieldInstances: []RawFieldInstance, layerInstances: []LayerInstance };
const World = struct { levels: []Level };

const PointType = struct { cx: i32, cy: i32 };

var t: u32 = 0;
var levels: std.ArrayList(SavedLevel) = undefined;
var ouchie = false;
export fn BOOT() void {
    fba = std.heap.FixedBufferAllocator.init(&buf);
    allocator = fba.allocator();

    const world = json.parseFromSlice(World, allocator, file, .{ .ignore_unknown_fields = true, .allocate = .alloc_if_needed }) catch |err| {
        tic.tracef("{any}", .{err});
        tic.trace("sadge");
        ouchie = true;
        return;
    };
    defer world.deinit();

    levels = std.ArrayList(SavedLevel).init(allocator);

    @memset(tic.MAP, 0);
    for (world.value.levels) |level| {
        const tile_x = @divFloor(level.worldX, 8);
        const tile_y = @divFloor(level.worldY, 8);
        const tile_w = @divFloor(level.pxWid, 8);
        const tile_h = @divFloor(level.pxHei, 8);
        const pix_x = level.worldX;
        const pix_y = level.worldY;
        var cam_mode = SavedLevel.CamMode.locked;
        var death_bottom = true;
        var entities = std.ArrayList(SavedLevel.Entity).init(allocator);
        for (level.fieldInstances) |field| {
            if (std.mem.eql(u8, field.__identifier, "CameraType")) {
                const v = field.__value.string;
                if (std.mem.eql(u8, v, "Locked")) {
                    cam_mode = .locked;
                } else if (std.mem.eql(u8, v, "FollowX")) {
                    cam_mode = .follow_x;
                } else if (std.mem.eql(u8, v, "FollowY")) {
                    cam_mode = .follow_y;
                } else if (std.mem.eql(u8, v, "FreeFollow")) {
                    cam_mode = .free_follow;
                }
            } else if (std.mem.eql(u8, field.__identifier, "DeathBottom")) {
                death_bottom = field.__value.bool;
            }
        }
        // freeing? what's that?
        // defer entities.deinit();
        for (level.layerInstances) |layer| {
            if (std.mem.eql(u8, layer.__identifier, "TileMap")) {
                // yippee!
                for (layer.autoLayerTiles) |tile| {
                    const tx = @divFloor(tile.px[0], 8);
                    const ty = @divFloor(tile.px[1], 8);
                    const da_tile: u32 = switch (tile.t) {
                        0 => 39,
                        1 => 40,
                        2 => 41,
                        3 => 42,
                        4 => 43,
                        5 => 44,
                        6 => 45,
                        7 => 55,
                        8 => 56,
                        9 => 57,
                        10 => 58,
                        11 => 59,
                        12 => 60,
                        13 => 61,
                        14 => 71,
                        15 => 72,
                        16 => 73,
                        17 => 74,
                        18 => 75,
                        19 => 76,
                        20 => 77,
                        21 => 87,
                        22 => 88,
                        23 => 89,
                        24 => 90,
                        else => {
                            ouchie = true;
                            tic.trace("not a real tile!");
                            return;
                        },
                    };
                    tic.mset(tile_x + tx, tile_y + ty, da_tile);
                }
            } else if (std.mem.eql(u8, layer.__identifier, "Entities")) {
                for (layer.entityInstances) |entity| {
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
                                s_kind = @intFromFloat(field.__value.float);
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
                                s_kind = @intFromFloat(field.__value.float);
                            } else if (std.mem.eql(u8, field.__identifier, "target")) {
                                const res = json.parseFromValue(PointType, allocator, field.__value, .{}) catch {
                                    ouchie = true;
                                    tic.trace("no!");
                                    continue;
                                };
                                defer res.deinit();
                                target = res.value;
                            }
                        }
                        kind = .{ .switch_door = .{ .kind = s_kind, .target = .{ .x = pix_x + target.cx * 8, .y = pix_y + target.cy * 8 } } };
                    } else if (std.mem.eql(u8, entity.__identifier, "TrafficBlock")) {
                        var target: PointType = .{ .cx = 0, .cy = 0 };
                        for (entity.fieldInstances) |field| {
                            if (std.mem.eql(u8, field.__identifier, "target")) {
                                const res = json.parseFromValue(PointType, allocator, field.__value, .{}) catch {
                                    ouchie = true;
                                    tic.trace("no!");
                                    continue;
                                };
                                defer res.deinit();
                                target = res.value;
                            }
                        }
                        kind = .{ .traffic_block = .{ .target = .{ .x = pix_x + target.cx * 8, .y = pix_y + target.cy * 8 } } };
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
                    }

                    if (kind) |k| {
                        entities.append(.{ .x = ex, .y = ey, .w = ew, .h = eh, .kind = k }) catch unreachable;
                    }
                }
            }
        }
        levels.append(.{ .x = tile_x, .y = tile_y, .width = tile_w, .height = tile_h, .entities = entities.items, .cam_mode = cam_mode, .death_bottom = death_bottom }) catch unreachable;
    }
}

export fn TIC() void {
    tic.cls(0);
    switch (t) {
        0 => tic.sync(.{ .bank = 0, .sections = .{ .map = true }, .toCartridge = true }),
        1 => {
            if (!ouchie) {
                @memset(tic.MAP, 0);
                var stream = std.io.fixedBufferStream(tic.MAP);
                s2s.serialize(stream.writer(), []SavedLevel, levels.items) catch |err| {
                    tic.tracef("{any}", .{err});
                };
                tic.sync(.{ .bank = 7, .sections = .{ .map = true }, .toCartridge = true });
            }
        },
        else => {
            if (ouchie) {
                _ = tic.print("oopsies!", 0, 0, .{});
            } else {
                _ = tic.print("done :)", 0, 0, .{});
            }
        },
    }
    t += 1;
}

export fn BDR() void {}

export fn OVR() void {}
