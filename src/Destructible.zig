const tdraw = @import("draw.zig");
const tic = @import("common").tic;
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Player = @import("Player.zig");
const Allocator = std.mem.Allocator;
const sheets = @import("sheets.zig");

const vtable: GameObject.VTable = .{ .ptr_draw = @ptrCast(&draw), .get_object = @ptrCast(&get_object), .destroy = @ptrCast(&destroy), .can_touch = &can_touch, .touch = &touch, .shot = &shot };
const shot_vtable: GameObject.VTable = .{ .ptr_draw = @ptrCast(&draw_shotonly), .get_object = @ptrCast(&get_object), .destroy = @ptrCast(&destroy), .shot = &shot };
pub fn draw(self: *GameObject) void {
    self.game_state.draw_sprite(sheets.destructible.items[0], self.x, self.y, .{});
}
fn draw_shotonly(self: *GameObject) void {
    self.game_state.draw_sprite(sheets.destructible_gun.items[0], self.x, self.y, .{});
}
fn get_object(self: *GameObject) *GameObject {
    return self;
}
pub fn create(allocator: std.mem.Allocator, x: i32, y: i32, shot_only: bool, state: *GameState) !*GameObject {
    var self = try allocator.create(GameObject);
    // cursed
    self.* = GameObject.create(state, x, y);
    self.solid = true;
    self.hit_x = 0;
    self.hit_y = 0;
    self.hit_w = 16;
    self.hit_h = 16;
    self.destroyed = false;
    self.touchable = true;
    self.shootable = true;

    const node = try state.wrap_node(.{ .ptr = self, .table = if (shot_only) shot_vtable else vtable });
    state.objects.append(node);

    return self;
}

fn destroy(self: *GameObject, allocator: Allocator) void {
    allocator.destroy(self);
}

fn die(self: *GameObject) void {
    self.destroyed = true;
    tic.sfx(6, .{ .duration = 10, .volume = 6 });
}

fn shot(ctx: *anyopaque, strength: u8) void {
    _ = strength;
    die(@alignCast(@ptrCast(ctx)));
}

fn touch(ctx: *anyopaque, player: *Player) void {
    const self: *GameObject = @alignCast(@ptrCast(ctx));
    if (player.state == .dash) {
        die(self);
    }
}

fn can_touch(ctx: *anyopaque, player: *Player) bool {
    _ = ctx;
    return player.state == .dash;
}
