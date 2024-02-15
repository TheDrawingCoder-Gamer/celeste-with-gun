const Spike = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const tic = @import("tic80.zig");
const tdraw = @import("draw.zig");

const vtable: GameObject.VTable = .{ .destroy = &destroy, .ptr_draw = &draw, .ptr_update = &GameObject.noUpdate, .get_object = &get_object };
pub const Direction = enum(u2) {
    up = 0,
    right = 1,
    down = 2,
    left = 3,
};

game_object: GameObject,
direction: Direction,

pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, dir: Direction) !*Spike {
    var obj = GameObject.create(state, x, y);
    obj.hit_x = switch (dir) {
        .down, .up, .right => 0,
        .left => 6,
    };
    obj.hit_y = switch (dir) {
        .down, .left => 0,
        .right => 0,
        .up => 6,
    };
    obj.hit_w = switch (dir) {
        .up, .down => 8,
        .left, .right => 2,
    };
    obj.hit_h = switch (dir) {
        .up, .down => 2,
        .left, .right => 8,
    };
    obj.hazard = switch (dir) {
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
    };
    const self = try allocator.create(Spike);
    self.direction = dir;
    self.game_object = obj;

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *Spike = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}
fn destroy(self: *anyopaque, allocator: Allocator) void {
    const cur: *Spike = @alignCast(@ptrCast(self));
    allocator.destroy(cur);
}

fn draw(ctx: *anyopaque) void {
    const self: *Spike = @alignCast(@ptrCast(ctx));
    self.game_object.game_state.draw_spr(290, self.game_object.x, self.game_object.y, .{ .rotate = @enumFromInt(@intFromEnum(self.direction)) });
}
