const GameState = @This();

const GameObject = @import("GameObject.zig");
const std = @import("std");
const tic = @import("tic80.zig");
const Level = @import("Level.zig");
const Player = @import("Player.zig");
const Screenwipe = @import("Screenwipe.zig");
const types = @import("types.zig");
const Voice = @import("Audio.zig").Voice;

pub const ObjectList = std.DoublyLinkedList(GameObject.IsGameObject);

objects: ObjectList,
time: u64 = 0,
allocator: std.mem.Allocator,
camera_x: i32 = 0,
camera_y: i32 = 0,
pan_speed: i16 = 5,
loaded_level: Level = undefined,
players: []const *Player,
screenwipe: Screenwipe = .{},
panning: bool = false,
current_player_spawn: types.Point = .{ .x = 0, .y = 0 },
voice: *Voice,
// voice for extra effects
aux_voice: *Voice,

pub fn init(allocator: std.mem.Allocator, players: []const *Player, voice: *Voice, aux_voice: *Voice) GameState {
    const list: std.DoublyLinkedList(GameObject.IsGameObject) = .{};
    return .{ .allocator = allocator, .objects = list, .players = players, .voice = voice, .aux_voice = aux_voice };
}

pub fn wrap_node(self: *GameState, table: GameObject.IsGameObject) !*ObjectList.Node {
    var node = try self.allocator.create(ObjectList.Node);
    node.data = table;
    return node;
}

pub fn draw_spr(self: *GameState, id: i32, world_x: i32, world_y: i32, args: tic.SpriteArgs) void {
    tic.spr(id, world_x - self.camera_x, world_y - self.camera_y, args);
}

pub fn clean(self: *GameState) void {
    var it = self.objects.first;
    while (it) |node| : (it = node.next) {
        if (!node.data.obj().persistent) {
            self.objects.remove(node);
            node.data.destroy(self.allocator);
            self.allocator.destroy(node);
        }
    }
    self.screenwipe.reset();
}

fn remap(x: i32, y: i32, info: *tic.RemapInfo) void {
    _ = x;
    _ = y;
    if (tic.fget(info.index, 1))
        info.index = 0;
}

pub fn camera(self: *const GameState) types.Point {
    return .{ .x = self.camera_x, .y = self.camera_y };
}
pub fn snap_cam(self: *GameState, x: i32, y: i32) void {
    self.camera_x = x;
    self.camera_y = y;
}

pub fn center_x(self: *GameState, on: i32) void {
    const half_width = tic.WIDTH / 2;
    const x_center = self.camera_x + half_width;

    if (on > x_center) {
        self.camera_x = @min(on - half_width, (self.loaded_level.x + self.loaded_level.width) * 8 - tic.WIDTH);
    } else {
        self.camera_x = @max(on - half_width, self.loaded_level.x * 8);
    }
}
pub fn center_y(self: *GameState, on: i32) void {
    const half_height = tic.HEIGHT / 2;
    const y_center = self.camera_y + half_height;

    if (on > y_center) {
        self.camera_y = @min(on - half_height, (self.loaded_level.y + self.loaded_level.height) * 8 - tic.HEIGHT);
    } else {
        self.camera_y = @max(on - half_height, self.loaded_level.y * 8);
    }
}

pub fn forall_objects(self: *GameState, data: *anyopaque, func: *const fn (*anyopaque, GameObject.IsGameObject) void) void {
    {
        var it = self.objects.first;
        while (it) |node| : (it = node.next) {
            func(data, node.data);
        }
    }
    for (self.players) |player| {
        func(data, .{ .ptr = @ptrCast(player), .table = Player.vtable });
    }
}
pub fn loop(self: *GameState) void {
    tic.cls(13);
    const should_update = self.screenwipe.infade > 45 and !self.panning and self.screenwipe.level_wipe > 45;
    // krill issue

    const ccx = @divFloor(self.camera_x, 8);
    const ccy = @divFloor(self.camera_y, 8);

    tic.map(.{ .remap = &remap, .x = ccx, .w = 32, .y = ccy, .h = 18, .sx = -@rem(self.camera_x, 8), .sy = -@rem(self.camera_y, 8) });
    {
        var it = self.objects.first;
        while (it) |node| : (it = node.next) {
            const obj = node.data;
            if (should_update)
                obj.update();
            obj.draw();

            if (obj.obj().destroyed) {
                self.objects.remove(node);
                obj.destroy(self.allocator);
                self.allocator.destroy(node);
            }
        }
    }
    for (self.players) |player| {
        if (should_update)
            player.update();
        player.draw();
        if (player.game_object.y > (self.loaded_level.y + self.loaded_level.height) * 8) {
            if (player.state != .death) {
                player.die();
                continue;
            }
        }

        if ((player.game_object.x > (self.loaded_level.x + self.loaded_level.width) * 8) or (player.game_object.x < self.loaded_level.x * 8) or (player.game_object.y > (self.loaded_level.y + self.loaded_level.height) * 8) or (player.game_object.y < self.loaded_level.y * 8)) {
            // TODO: Multiplayer
            const room = Level.find_at(player.game_object.x, player.game_object.y);
            if (room) |r| {
                // screen refill
                player.can_dash = true;
                r.load_level(self).load() catch unreachable;
            } else {
                // ???
                if (player.state != .death) {
                    player.die();
                }
            }
        }
    }
    if (self.screenwipe.level_wipe == 44) {
        self.screenwipe.infade = 0;
    }
    self.screenwipe.update();
    self.screenwipe.draw();
    self.time += 1;

    switch (self.loaded_level.cam_mode) {
        .locked => {},
        .follow_x => {
            self.center_x(self.players[0].game_object.x);
        },
        .follow_y => {
            self.center_y(self.players[0].game_object.y);
        },
        .free_follow => {
            const host = self.players[0];
            self.center_x(host.game_object.x);
            self.center_y(host.game_object.y);
        },
    }
}
const RaycastInfo = struct {
    box: types.Box,
    closest: *?f32,
    point: *types.PointF,
    ray_segment: types.LineSegment,
};
fn raycast_foreach(info: *anyopaque, obj: GameObject.IsGameObject) void {
    const o = obj.obj();
    if (!o.solid) return;
    const data: *RaycastInfo = @alignCast(@ptrCast(info));

    if (!o.overlaps_box(0, 0, data.box))
        return;

    for (o.world_hitbox().segments()) |segment| {
        if (data.ray_segment.intersects(segment)) |int_point| {
            const d = data.ray_segment.start.distance_squared(int_point);
            if (data.closest.*) |c| {
                if (c > d) {
                    data.closest.* = d;
                    data.point.* = int_point;
                }
            } else {
                data.closest.* = d;
                data.point.* = int_point;
            }
        }
    }
}
pub const RayHit = struct { pos: types.PointF, distance: f32, angle: f32 };
pub fn raycast(self: *GameState, start: types.PointF, angle: f32, distance: f32) ?RayHit {
    const p0 = start;
    const direction = types.PointF.from_radians(angle);
    const p1 = start.add(direction.times(distance));
    const ray_segment: types.LineSegment = .{ .start = p0, .end = p1 };
    const box = types.Box.aabb(@intFromFloat(p0.x), @intFromFloat(p0.y), @intFromFloat(p1.x), @intFromFloat(p1.y)).inflate(1);

    var closest: ?f32 = null;
    var point: types.PointF = start;

    {
        var i: i32 = @divFloor(box.x, 8);
        const imax: i32 = @divFloor(box.x + box.w, 8);
        const jmin = @divFloor(box.y, 8);
        const jmax = @divFloor(box.y + box.h, 8);

        while (i < imax) : (i += 1) {
            var j = jmin;
            while (j < jmax) : (j += 1) {
                if (tic.fget(tic.mget(i, j), 0)) {
                    const segments = [_]types.LineSegment{ .{ .start = types.Point.as_float(.{ .x = i * 8, .y = j * 8 }), .end = types.Point.as_float(.{ .x = (i + 1) * 8, .y = j * 8 }) }, .{ .start = types.Point.as_float(.{ .x = i * 8, .y = j * 8 }), .end = types.Point.as_float(.{ .x = i * 8, .y = (j + 1) * 8 }) }, .{ .start = types.Point.as_float(.{ .x = (i + 1) * 8, .y = j * 8 }), .end = types.Point.as_float(.{ .x = (i + 1) * 8, .y = (j + 1) * 8 }) }, .{ .start = types.Point.as_float(.{ .x = i * 8, .y = (j + 1) * 8 }), .end = types.Point.as_float(.{ .x = (i + 1) * 8, .y = (j + 1) * 8 }) } };
                    for (segments) |segment| {
                        if (ray_segment.intersects(segment)) |int_point| {
                            const d = start.distance_squared(int_point);
                            if (closest) |c| {
                                if (c > d) {
                                    closest = d;
                                    point = int_point;
                                }
                            } else {
                                closest = d;
                                point = int_point;
                            }
                        }
                    }
                }
            }
        }
    }

    var info: RaycastInfo = .{ .closest = &closest, .box = box, .ray_segment = ray_segment, .point = &point };

    self.forall_objects(@ptrCast(&info), &raycast_foreach);

    if (closest) |c| {
        return .{ .pos = point, .distance = std.math.sqrt(c), .angle = std.math.pi + angle };
    }
    return null;
}
