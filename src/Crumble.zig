const Crumble = @This();

const tdraw = @import("draw.zig");
const tic = @import("tic80.zig");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const vtable: GameObject.VTable = .{ .ptr_draw = &draw, .destroy = &destroy, .get_object = &get_object, .ptr_update = &update, .ptr_die = &die };

game_object: GameObject,
t_alive: u8 = 0,
dying: bool = false,
start_x: i32,
start_y: i32,

fn draw(ctx: *anyopaque) void {
    const self: *Crumble = @alignCast(@ptrCast(ctx));
    tdraw.set2bpp();
    // defer as we only draw in 2bpp
    defer tdraw.set4bpp();
    self.game_object.game_state.draw_spr(800 + @as(i32, @divFloor(self.t_alive, 4)), self.game_object.x, self.game_object.y, .{ .transparent = &.{0} });
}

fn destroy(ctx: *anyopaque, allocator: Allocator) void {
    const self: *Crumble = @alignCast(@ptrCast(ctx));
    allocator.destroy(self);
}

fn update(ctx: *anyopaque) void {
    const self: *Crumble = @alignCast(@ptrCast(ctx));
    if (self.dying) {
        self.t_alive += 1;
        if (self.t_alive > 20) {
            self.game_object.x = -32;
            self.game_object.y = -32;
            self.game_object.solid = false;
        }
        if (self.t_alive > 180) {
            self.t_alive = 180;
            var can_respawn = true;
            self.game_object.x = self.start_x;
            self.game_object.y = self.start_y;
            if (self.game_object.first_overlap(0, 0)) |_| {
                can_respawn = false;
            }

            if (can_respawn) {
                self.dying = false;
                self.t_alive = 0;
                self.game_object.solid = true;
                // todo: sfx
            } else {
                self.game_object.x = -32;
                self.game_object.y = -32;
            }
        }
    }
}

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *Crumble = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}

fn die(ctx: *anyopaque) void {
    const self: *Crumble = @alignCast(@ptrCast(ctx));
    self.dying = true;
    tic.sfx(6, .{ .volume = 6, .duration = 8 });
}

pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32) !*Crumble {
    var obj = GameObject.create(state, x, y);
    obj.special_type = .crumble;
    obj.solid = true;

    const self = try allocator.create(Crumble);
    self.* = .{
        .game_object = obj,
        .start_x = obj.x,
        .start_y = obj.y,
    };

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}
