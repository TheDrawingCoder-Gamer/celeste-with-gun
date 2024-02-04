const Bullet = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const tic = @import("tic80.zig");
const tdraw = @import("draw.zig");

var amount: u8 = 0;

pub const Direction = enum {
    up,
    left,
    down,
    right,

    pub fn axis_x(self: Direction) i2 {
        return switch (self) {
            .up, .down => 0,
            .left => -1,
            .right => 1,
        };
    }
    pub fn axis_y(self: Direction) i2 {
        return switch (self) {
            .left, .right => 0,
            .up => -1,
            .down => 1,
        };
    }
};

const vtable: GameObject.VTable = .{ .ptr_draw = @ptrCast(&draw), .get_object = @ptrCast(&get_object), .ptr_update = @ptrCast(&update), .destroy = @ptrCast(&destroy) };
player: u2,
game_object: GameObject,
direction: Direction,
rotation: tic.Rotate,

pub fn draw(self: *Bullet) void {
    Player.pallete(self.player);
    tdraw.set2bpp();
    tic.spr(536, self.game_object.x, self.game_object.y, .{ .transparent = &.{0}, .rotate = self.rotation });
    Player.reset_pallete();
    tdraw.set4bpp();
}
fn die_on_collide(self: *Bullet, moved: i32, target: i32) bool {
    _ = moved;
    _ = target;
    const item = self.game_object.first_overlap(self.direction.axis_x(), self.direction.axis_y());
    if (item) |obj| {
        if (obj.obj().destructable) {
            obj.obj().destroyed = true;
        }
    }
    self.game_object.destroyed = true;
    return true;
}
pub fn update(self: *Bullet) void {
    switch (self.direction) {
        .left, .right => {
            _ = vtable.move_x(self, @floatFromInt(self.direction.axis_x()), @ptrCast(&die_on_collide));
        },
        .up, .down => {
            _ = vtable.move_y(self, @floatFromInt(self.direction.axis_y()), @ptrCast(&die_on_collide));
        },
    }
}

fn get_object(self: *Bullet) *GameObject {
    return &self.game_object;
}
pub fn create(allocator: std.mem.Allocator, state: *GameState, x: i32, y: i32, player: u2, dir: Direction) !*Bullet {
    if (amount > 32)
        return error.TooMany;
    var obj = GameObject.create(state, x, y);
    obj.hit_w = 4;
    obj.hit_h = 4;
    obj.hit_x = -2;
    obj.hit_y = -4;
    const self = try allocator.create(Bullet);
    self.player = player;
    self.game_object = obj;
    self.direction = dir;
    self.rotation = switch (self.direction) {
        .up => .by270,
        .right => .no,
        .down => .by90,
        .left => .by180,
    };

    amount += 1;
    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn destroy(self: *Bullet, allocator: Allocator) void {
    allocator.destroy(self);
    amount -= 1;
}
