const SwitchDoor = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const tic = @import("tic80.zig");
const Allocator = std.mem.Allocator;

const table: GameObject.VTable = .{
    .get_object = &get_object,
    .destroy = &destroy,
    .ptr_draw = &draw,
};
game_object: GameObject,
kind: u8 = 0,

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}

fn destroy(ctx: *anyopaque, allocator: Allocator) void {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    allocator.destroy(self);
}

pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, kind: u8) !*SwitchDoor {
    var obj = GameObject.create(state, x, y);
    obj.solid = true;
    obj.hit_x = 0;
    obj.hit_y = 0;
    obj.hit_w = 8;
    obj.hit_h = 8;
    obj.special_type = .sheild_door;

    const self = try allocator.create(SwitchDoor);
    self.game_object = obj;
    self.kind = kind;

    const node = try state.wrap_node(.{ .ptr = self, .table = table });
    state.objects.append(node);

    return self;
}

fn draw(ctx: *anyopaque) void {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    self.game_object.game_state.draw_spr(291, self.game_object.x, self.game_object.y, .{});
}
