const tdraw = @import("draw.zig");
const tic = @import("tic80.zig");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const vtable: GameObject.VTable = .{ .ptr_draw = @ptrCast(&draw), .ptr_update = &GameObject.noUpdate, .get_object = @ptrCast(&get_object), .destroy = @ptrCast(&destroy), .ptr_die = &die };

pub fn draw(self: *GameObject) void {
    self.game_state.draw_spr(272, self.x, self.y, .{ .w = 2, .h = 2, .transparent = &.{0} });
}
fn get_object(self: *GameObject) *GameObject {
    return self;
}
pub fn create(allocator: std.mem.Allocator, x: i32, y: i32, state: *GameState) !*GameObject {
    var self = try allocator.create(GameObject);
    // cursed
    self.* = GameObject.create(state, x * 8, y * 8);
    self.solid = true;
    self.hit_x = 0;
    self.hit_y = 0;
    self.hit_w = 16;
    self.hit_h = 16;
    self.destroyed = false;

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn destroy(self: *GameObject, allocator: Allocator) void {
    allocator.destroy(self);
}

fn die(ctx: *anyopaque) void {
    const self: *GameObject = @alignCast(@ptrCast(ctx));
    self.destroyed = true;
}
