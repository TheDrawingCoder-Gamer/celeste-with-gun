const Bullet = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const tic = @import("common").tic;
const tdraw = @import("draw.zig");
const sheets = @import("sheets.zig");

var amount: u8 = 0;

pub const Direction = enum {
    up_left,
    up,
    up_right,
    left,
    right,
    down_left,
    down,
    down_right,

    pub fn axis_x(self: Direction) i2 {
        return switch (self) {
            .up, .down => 0,
            .left, .up_left, .down_left => -1,
            .right, .up_right, .down_right => 1,
        };
    }
    pub fn axis_y(self: Direction) i2 {
        return switch (self) {
            .left, .right => 0,
            .up, .up_left, .up_right => -1,
            .down, .down_left, .down_right => 1,
        };
    }
};

const vtable: GameObject.VTable = .{ .ptr_draw = @ptrCast(&draw), .get_object = @ptrCast(&get_object), .ptr_update = @ptrCast(&update), .destroy = @ptrCast(&destroy) };
player: u2,
game_object: GameObject,
direction: Direction,
rotation: tic.Rotate,
spr: i32,
ttl: i32,

pub fn draw(self: *Bullet) void {
    Player.pallete(self.player);
    tdraw.set2bpp();
    self.game_object.game_state.draw_spr(self.spr, self.game_object.x, self.game_object.y, .{ .transparent = &.{0}, .rotate = self.rotation });
    Player.reset_pallete();
    tdraw.set4bpp();
}

fn die_on_collide(self: *Bullet, moved: i32, target: i32) bool {
    _ = moved;
    _ = target;
    const item = self.game_object.first_overlap(self.direction.axis_x(), self.direction.axis_y());
    if (item) |obj| {
        if (obj.obj().shootable) {
            obj.shot(50);
        }
    }
    self.game_object.destroyed = true;
    return true;
}
pub fn update(self: *Bullet) void {
    // if ttl is -1 that means infinite ttl
    if (self.ttl > 0) {
        self.ttl -= 1;
    }
    if (self.ttl == 0) {
        self.game_object.destroyed = true;
        return;
    }
    _ = vtable.move_x(self, self.game_object.speed_x, @ptrCast(&die_on_collide));
    _ = vtable.move_y(self, self.game_object.speed_y, @ptrCast(&die_on_collide));
    if (self.game_object.destroyed)
        return;
    {
        var it = self.game_object.game_state.objects.first;
        while (it) |node| : (it = node.next) {
            var obj = node.data;
            const gameobj = obj.obj();
            if (gameobj.shootable and !gameobj.destroyed and self.game_object.hurtboxes_touch(obj, 0, 0)) {
                obj.shot(50);
                self.game_object.destroyed = true;
                return;
            }
        }
    }
}

fn get_object(self: *Bullet) *GameObject {
    return &self.game_object;
}
pub fn create(allocator: std.mem.Allocator, state: *GameState, x: i32, y: i32, player: u2, dir: Direction, ttl: i32) !*Bullet {
    if (amount > 32)
        return error.TooMany;
    var obj = GameObject.create(state, x, y);
    obj.hit_x = 3;
    obj.hit_y = 3;
    obj.hit_w = 2;
    obj.hit_h = 2;
    obj.hurtbox = .{ .x = -1, .y = -1, .w = 9, .h = 9 };
    obj.speed_x = @floatFromInt(@as(i32, dir.axis_x()) * 8);
    obj.speed_y = @floatFromInt(@as(i32, dir.axis_y()) * 8);
    const self = try allocator.create(Bullet);
    self.player = player;
    self.game_object = obj;
    self.direction = dir;
    self.rotation = switch (self.direction) {
        .up, .up_left => .by270,
        .right, .up_right => .no,
        .down, .down_right => .by90,
        .left, .down_left => .by180,
    };
    self.spr = blk: {
        const data: u1 = switch (self.direction) {
            .up, .right, .down, .left => 0,
            else => 1,
        };
        break :blk sheets.bullet.items[data];
    };
    self.ttl = ttl;

    amount += 1;
    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn destroy(self: *Bullet, allocator: Allocator) void {
    allocator.destroy(self);
    amount -= 1;
}
