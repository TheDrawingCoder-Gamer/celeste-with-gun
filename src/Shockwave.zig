const Shockwave = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const tic = @import("common").tic;
const tdraw = @import("draw.zig");
const types = @import("types.zig");
const sheets = @import("sheets.zig");

var amount: u8 = 0;
pub const SHOCKWAVE_STRENGTH = 10;

const Direction = types.CardinalDir;

const vtable: GameObject.VTable = .{ .ptr_draw = &draw, .get_object = @ptrCast(&get_object), .ptr_update = @ptrCast(&update), .destroy = @ptrCast(&destroy) };
player: u2,
game_object: GameObject,
direction: Direction,
root: Direction,
flip: tic.Flip,
rotation: tic.Rotate,
ttl: i32,

fn draw(ctx: *anyopaque) void {
    const self: *Shockwave = @alignCast(@ptrCast(ctx));
    Player.pallete(self.player);
    tdraw.set2bpp();
    self.game_object.game_state.draw_sprite(sheets.bullet.items[2], self.game_object.x, self.game_object.y, .{ .rotate = self.rotation, .flip = self.flip });
    Player.reset_pallete();
    tdraw.set4bpp();
}

fn die_on_collide(self: *Shockwave, moved: i32, target: i32) bool {
    _ = moved;
    _ = target;
    const item = self.game_object.first_overlap(self.direction.x(), self.direction.y());
    if (item) |obj| {
        if (obj.obj().shootable) {
            obj.shot(SHOCKWAVE_STRENGTH);
        }
    }
    self.game_object.destroyed = true;
    return true;
}
pub fn update(self: *Shockwave) void {
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
    // moved off surface
    if (!self.game_object.check_solid(self.root.x(), self.root.y())) {
        self.game_object.destroyed = true;
        return;
    }
    {
        var it = self.game_object.game_state.objects.first;
        while (it) |node| : (it = node.next) {
            var obj = node.data;
            const gameobj = obj.obj();
            if (gameobj.shootable and !gameobj.destroyed and self.game_object.hurtboxes_touch(obj, 0, 0)) {
                obj.shot(SHOCKWAVE_STRENGTH);
                self.game_object.destroyed = true;
                return;
            }
        }
    }
}

fn get_object(self: *Shockwave) *GameObject {
    return &self.game_object;
}
pub fn create(allocator: std.mem.Allocator, state: *GameState, x: i32, y: i32, player: u2, dir: Direction, root: Direction, ttl: i32) !*Shockwave {
    if (amount > 32)
        return error.TooMany;
    var obj = GameObject.create(state, x, y);
    const hit = switch (root) {
        .up => .{ @as(i32, 4), @as(i32, 0) },
        .down => .{ 4, 6 },
        .left => .{ 0, 4 },
        .right => .{ 6, 4 },
    };
    obj.hit_x = hit[0];
    obj.hit_y = hit[1];
    obj.hit_w = 2;
    obj.hit_h = 2;
    obj.hurtbox = .{ .x = 1, .y = 1, .w = 7, .h = 7 };
    obj.speed_x = @floatFromInt(@as(i32, dir.x()) * 4);
    obj.speed_y = @floatFromInt(@as(i32, dir.y()) * 4);
    const self = try allocator.create(Shockwave);
    self.player = player;
    self.game_object = obj;
    self.direction = dir;
    self.root = root;
    const flip_rot: struct { tic.Flip, tic.Rotate } = switch (root) {
        .up, .down => res: {
            const r1: u2 = if (root == .up) 2 else 0;
            const r2: u2 = if (dir == .left) 0 else 1;
            break :res .{ @as(tic.Flip, @enumFromInt(r1 | r2)), tic.Rotate.no };
        },
        .left => .{ if (dir == .up) .no else .vertical, tic.Rotate.by90 },
        .right => .{ if (dir == .down) tic.Flip.no else tic.Flip.vertical, tic.Rotate.by270 },
    };
    self.flip = flip_rot[0];
    self.rotation = flip_rot[1];
    self.ttl = ttl;

    amount += 1;
    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn destroy(self: *Shockwave, allocator: Allocator) void {
    allocator.destroy(self);
    amount -= 1;
}
