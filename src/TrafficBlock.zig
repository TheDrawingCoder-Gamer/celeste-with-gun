const TrafficBlock = @This();

const tic = @import("tic80.zig");
const Player = @import("Player.zig");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const types = @import("types.zig");
const std = @import("std");
const Solid = @import("Solid.zig");

const vtable: GameObject.VTable = .{ .destroy = &destroy, .can_touch = &can_touch, .touch = &touch, .ptr_draw = &draw, .ptr_update = &update, .get_object = &get_object };

const State = enum { idle, advancing, retreating, stalled };
game_object: GameObject,
state: State = .idle,
t_progress: u8 = 0,
start: types.Point,
target: types.Point,
width: u31,
height: u31,
last_touched: u64 = 0,
lerp: f32 = 0,

pub fn create(state: *GameState, x: i32, y: i32, w: u31, h: u31, target: types.Point) !*TrafficBlock {
    var obj = GameObject.create(state, x, y);
    obj.hit_w = 8 * w;
    obj.hit_h = 8 * h;
    obj.solid = true;
    obj.touchable = true;

    const self = try state.allocator.create(TrafficBlock);
    self.* = .{ .start = .{ .x = x, .y = y }, .target = target, .game_object = obj, .width = w, .height = h };

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn destroy(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));

    allocator.destroy(self);
}

fn can_touch(ctx: *anyopaque, player: *Player) bool {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));
    if (self.game_object.game_state.time <= self.last_touched + 1) {
        return false;
    }
    if (player.game_object.overlaps_box(0, 1, self.game_object.world_hitbox())) {
        self.last_touched = self.game_object.game_state.time;
        return self.state == .idle;
    }
    return false;
}

fn touch(ctx: *anyopaque, player: *Player) void {
    _ = player;
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));

    self.last_touched = self.game_object.game_state.time;
    self.start_advance();
}

fn start_advance(self: *TrafficBlock) void {
    self.state = .advancing;
    const velocity = self.target.add(self.start.times(-1)).as_float().normalized().times(5);
    self.game_object.set_velocity(velocity);
}

fn stall(self: *TrafficBlock) void {
    self.state = .stalled;
    self.t_progress = 30;
    self.game_object.set_velocity(.{ .x = 0, .y = 0 });
}

fn stop(self: *TrafficBlock) void {
    self.state = .idle;
    self.game_object.set_velocity(.{ .x = 0, .y = 0 });
}
fn start_retreat(self: *TrafficBlock) void {
    self.state = .retreating;
    const velocity = self.target.add(self.start.times(-1)).as_float().normalized().times(-1);
    self.game_object.set_velocity(velocity);
}
fn approach(self: *TrafficBlock, speed: f32, target: types.PointF) bool {
    const start_point = self.game_object.point();
    const res = start_point.approach(speed, speed, target);
    Solid.move_to_point_with_speed(self.as_table(), res, res.add(start_point.times(-1)));

    return std.meta.eql(start_point, res);
}

fn as_table(self: *TrafficBlock) GameObject.IsGameObject {
    return .{ .ptr = self, .table = vtable };
}

fn update(ctx: *anyopaque) void {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));
    if (self.state == .idle)
        return;

    switch (self.state) {
        .idle => {},
        .advancing => {
            self.lerp = types.approach(self.lerp, 1, 2.0 / 60.0);
            if (self.lerp == 1.0) {
                self.stall();
            }
            const res = types.PointF.lerp(self.start.as_float(), self.target.as_float(), types.sine_in_out(self.lerp));
            Solid.move_to_point_once(self.as_table(), res);
        },
        .retreating => {
            self.lerp = types.approach(self.lerp, 0, 1.0 / 60.0);
            if (self.lerp == 0.0) {
                self.stop();
            }
            const res = types.PointF.lerp(self.start.as_float(), self.target.as_float(), types.sine_in_out(self.lerp));
            Solid.move_to_point_once(self.as_table(), res);
        },
        .stalled => {
            self.t_progress -= 1;
            if (self.t_progress <= 0) {
                self.start_retreat();
            }
        },
    }
}

fn draw(ctx: *anyopaque) void {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));

    const x = self.game_object.x - self.game_object.game_state.camera_x;
    const y = self.game_object.y - self.game_object.game_state.camera_y;
    tic.rect(x, y, self.width * 8, self.height * 8, 14);
    tic.rectb(x, y, self.width * 8, self.height * 8, 13);

    var point = @divFloor(self.width, 2) * 2 * 8;
    // if even
    if (self.width & 1 == 0) {
        point += 4;
    }
    const spr: i32 = switch (self.state) {
        .idle => 434,
        .advancing => 436,
        .retreating, .stalled => 435,
    };
    tic.spr(spr, x + point, y, .{ .transparent = &.{0} });
}

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}
