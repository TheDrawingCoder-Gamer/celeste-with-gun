const Spike = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const tic = @import("common").tic;
const tdraw = @import("draw.zig");
const types = @import("types.zig");

const vtable: GameObject.VTable = .{ .destroy = &destroy, .ptr_draw = &draw, .ptr_update = &GameObject.noUpdate, .get_object = &get_object };

game_object: GameObject,
direction: types.CardinalDir,
length: u31,
rotate: tic.Rotate,

pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, dir: types.CardinalDir, length: u31) !*Spike {
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
        .up, .down => 8 * length,
        .left, .right => 2,
    };
    obj.hit_h = switch (dir) {
        .up, .down => 2,
        .left, .right => 8 * length,
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
    self.rotate = switch (dir) {
        .up => .no,
        .right => .by90,
        .down => .by180,
        .left => .by270,
    };
    self.length = length;

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
    var i: u31 = 0;
    while (i < self.length) : (i += 1) {
        switch (self.direction) {
            .up, .down => {
                self.game_object.game_state.draw_spr(290, self.game_object.x + i * 8, self.game_object.y, .{ .rotate = self.rotate });
            },
            .left, .right => {
                self.game_object.game_state.draw_spr(290, self.game_object.x, self.game_object.y + i * 8, .{ .rotate = self.rotate });
            },
        }
    }
}
