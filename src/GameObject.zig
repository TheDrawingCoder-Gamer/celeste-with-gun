const GameObject = @This();

const tic80 = @import("common").tic;
const std = @import("std");
const Allocator = std.mem.Allocator;
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const types = @import("types.zig");

pub const HazardType = enum { none, all, left, up, right, down };
pub const IsGameObject = struct {
    ptr: *anyopaque,
    table: VTable,
    pub fn update(self: *const IsGameObject) void {
        self.table.ptr_update(self.ptr);
    }
    pub fn draw(self: *const IsGameObject) void {
        self.table.ptr_draw(self.ptr);
    }
    pub fn obj(self: *const IsGameObject) *GameObject {
        return self.table.get_object(self.ptr);
    }
    pub fn move_x(self: *const IsGameObject, x: f32, on_collide: ?*const fn (*anyopaque, i32, i32) bool) bool {
        return self.table.move_x(self.ptr, x, on_collide);
    }
    pub fn move_y(self: *const IsGameObject, y: f32, on_collide: ?*const fn (*anyopaque, i32, i32) bool) bool {
        return self.table.move_y(self.ptr, y, on_collide);
    }
    pub fn die(self: *const IsGameObject) void {
        self.table.ptr_die(self.ptr);
    }
    pub fn destroy(self: *const IsGameObject, alloc: Allocator) void {
        self.table.destroy(self.ptr, alloc);
    }
    pub fn touch(self: *const IsGameObject, player: *Player) void {
        self.table.touch(self.ptr, player);
    }
    pub fn can_touch(self: *const IsGameObject, player: *Player) bool {
        return self.table.can_touch(self.ptr, player);
    }
    pub fn shot(self: *const IsGameObject, strength: u8) void {
        self.table.shot(self.ptr, strength);
    }
    pub fn as_rider(self: *const IsGameObject) ?IRide {
        if (self.table.as_rider) |ride_it| {
            return ride_it(self.ptr);
        }
        return null;
    }
    pub fn squish(self: *const IsGameObject) void {
        if (self.table.squish) |sq| {
            sq(self.ptr);
            return;
        }
        self.die();
    }
};
pub const VTable = struct {
    get_object: *const fn (self: *anyopaque) *GameObject,
    ptr_update: *const fn (self: *anyopaque) void = &GameObject.noUpdate,
    ptr_draw: *const fn (self: *anyopaque) void = &GameObject.noDraw,
    ptr_die: *const fn (self: *anyopaque) void = &GameObject.noDie,
    destroy: *const fn (self: *anyopaque, allocator: std.mem.Allocator) void,
    touch: *const fn (self: *anyopaque, player: *Player) void = &GameObject.noTouch,
    can_touch: *const fn (self: *anyopaque, player: *Player) bool = &GameObject.noCanTouch,
    shot: *const fn (self: *anyopaque, strength: u8) void = &noShot,
    as_rider: ?*const fn (self: *anyopaque) IRide = null,
    squish: ?*const fn (self: *anyopaque) void = null,
    pub fn move_x(self: *const VTable, item: *anyopaque, x: f32, on_collide: ?*const fn (*anyopaque, moved: i32, target: i32) bool) bool {
        var gobj = self.get_object(item);
        gobj.remainder_x += x;
        var mx: i32 = @intFromFloat(gobj.remainder_x + 0.5);
        gobj.remainder_x -= @floatFromInt(mx);

        const total = mx;
        const mxs = std.math.sign(mx);
        while (mx != 0) {
            if (gobj.check_solid(mxs, 0)) {
                if (on_collide) |collide| {
                    return collide(item, total - mx, total);
                }
                return true;
            } else {
                gobj.x += mxs;
                mx -= mxs;
            }
        }

        return false;
    }
    pub fn move_y(self: *const VTable, item: *anyopaque, y: f32, on_collide: ?*const fn (*anyopaque, moved: i32, target: i32) bool) bool {
        var gobj = self.get_object(item);
        gobj.remainder_y += y;
        var my: i32 = @intFromFloat(gobj.remainder_y + 0.5);
        gobj.remainder_y -= @floatFromInt(my);

        const total = my;
        const mys = std.math.sign(my);
        while (my != 0) {
            if (gobj.check_solid(0, mys)) {
                if (on_collide) |collide| {
                    return collide(item, total - my, total);
                }
                return true;
            } else {
                gobj.y += mys;
                my -= mys;
            }
        }

        return false;
    }
};

// me too buddy, me too....
pub const IRide = struct {
    pub const VTable = struct {
        riding_platform_set_velocity: *const fn (self: *anyopaque, value: types.PointF) void,
        riding_platform_check: *const fn (self: *anyopaque, platform: IsGameObject) bool,
    };

    ctx: *anyopaque,
    table: *const IRide.VTable,

    pub fn riding_platform_set_velocity(self: *const IRide, value: types.PointF) void {
        self.table.riding_platform_set_velocity(self.ctx, value);
    }
    pub fn riding_platform_check(self: *const IRide, platform: IsGameObject) bool {
        return self.table.riding_platform_check(self.ctx, platform);
    }
};

pub const SpecialType = enum { sheild_toggle, sheild_door, player, none };
speed_x: f32 = 0,
speed_y: f32 = 0,
remainder_x: f32 = 0,
remainder_y: f32 = 0,
hit_x: i32 = 0,
hit_y: i32 = 0,
hit_w: u31 = 8,
hit_h: u31 = 8,
hurtbox: ?types.Box = null,
hazard: HazardType = .none,
solid: bool = false,
facing: i2 = 0,
x: i32,
y: i32,
id: i64,
destroyed: bool = false,
special_type: SpecialType = .none,
touchable: bool = false,
shootable: bool = false,
is_actor: bool = false,
game_state: *GameState,
// will never be freed on cleanup
persistent: bool = false,

pub fn overlaps(self: *GameObject, btable: IsGameObject, ox: i32, oy: i32) bool {
    const b = btable.obj();
    if (self == b)
        return false;
    return self.overlaps_box(ox, oy, b.world_hitbox());
}

pub fn world_hitbox(self: *const GameObject) types.Box {
    return .{ .x = self.x + self.hit_x, .y = self.y + self.hit_y, .w = self.hit_w, .h = self.hit_h };
}
pub fn world_hurtbox(self: *const GameObject) types.Box {
    if (self.hurtbox) |h| {
        return .{ .x = self.x + h.x, .y = self.y + h.y, .w = h.w, .h = h.h };
    }
    return self.world_hitbox();
}
pub fn overlaps_box(self: *GameObject, ox: i32, oy: i32, box: types.Box) bool {
    const selfbox = self.world_hitbox().offset(ox, oy);
    return selfbox.overlapping(box);
}
pub fn hurtboxes_touch(self: *GameObject, other: IsGameObject, ox: i32, oy: i32) bool {
    const b = other.obj();
    if (self == b)
        return false;
    return self.world_hurtbox().offset(ox, oy).overlapping(b.world_hurtbox());
}
pub fn contains(self: *GameObject, px: i32, py: i32) bool {
    return self.world_hitbox().contains(px, py);
}
pub fn check_solid(self: *GameObject, ox: i32, oy: i32) bool {
    const hitbox = self.world_hitbox().offset(ox, oy);
    var i: i32 = @divFloor(hitbox.x, 8);
    // in 4k?
    const imax = @divFloor(hitbox.right() - 1, 8);
    const jmin = @divFloor(hitbox.y, 8);
    const jmax = @divFloor(hitbox.bottom() - 1, 8);
    while (i <= imax) {
        var j: i32 = jmin;
        while (j <= jmax) {
            if (tic80.fget(tic80.mget(i, j), 0)) {
                return true;
            }
            j += 1;
        }

        i += 1;
    }

    var it = self.game_state.objects.first;
    while (it) |node| : (it = node.next) {
        var obj = node.data;
        const gameobj = obj.obj();
        if (gameobj.solid and gameobj != self and !gameobj.destroyed and self.overlaps(obj, ox, oy)) {
            return true;
        }
    }

    return false;
}

pub fn first_overlap(self: *GameObject, ox: i32, oy: i32) ?IsGameObject {
    var it = self.game_state.objects.first;
    while (it) |node| : (it = node.next) {
        const obj = node.data;
        const gameobj = obj.obj();
        if (gameobj != self and !gameobj.destroyed and self.overlaps(obj, ox, oy)) {
            return obj;
        }
    }
    return null;
}
pub fn on_collide_x(self: *GameObject, moved: i32, target: i32) bool {
    _ = moved;
    _ = target;
    self.remainder_x = 0;
    self.speed_x = 0;
    return true;
}

pub fn on_collide_y(self: *GameObject, moved: i32, target: i32) bool {
    _ = moved;
    _ = target;
    self.remainder_y = 0;
    self.speed_y = 0;
    return true;
}

pub fn move_raw(self: *GameObject, by: types.PointF) void {
    self.remainder_x += by.x;
    const mx: i32 = @intFromFloat(self.remainder_x + 0.5);
    self.remainder_x -= @floatFromInt(mx);
    self.x += mx;

    self.remainder_y += by.y;
    const my: i32 = @intFromFloat(self.remainder_y + 0.5);
    self.remainder_y -= @floatFromInt(my);
    self.y += my;
}
pub fn create(state: *GameState, x: i32, y: i32) GameObject {
    return .{ .game_state = state, .x = x, .y = y, .id = @divFloor(x, 8) + @divFloor(y, 8) * 128 };
}

pub fn point(self: *const GameObject) types.PointF {
    return .{ .x = @as(f32, @floatFromInt(self.x)) + self.remainder_x, .y = @as(f32, @floatFromInt(self.y)) + self.remainder_y };
}

pub fn velocity(self: *const GameObject) types.PointF {
    return .{ .x = self.speed_x, .y = self.speed_y };
}

pub fn set_velocity(self: *GameObject, da_velocity: types.PointF) void {
    self.speed_x = da_velocity.x;
    self.speed_y = da_velocity.y;
}

fn identity(self: *GameObject) *GameObject {
    return self;
}

pub fn noDestroy(ctx: *anyopaque, alloc: Allocator) void {
    _ = ctx;
    _ = alloc;
}
pub fn noUpdate(ctx: *anyopaque) void {
    _ = ctx;
}
pub fn noDie(ctx: *anyopaque) void {
    _ = ctx;
}

pub fn noTouch(ctx: *anyopaque, player: *Player) void {
    _ = ctx;
    _ = player;
}
pub fn noCanTouch(ctx: *anyopaque, player: *Player) bool {
    _ = ctx;
    _ = player;
    return false;
}
// me to anyone who gives me the slightest bit of attention
pub fn yesCanTouch(ctx: *anyopaque, player: *Player) bool {
    _ = ctx;
    _ = player;
    return true;
}

pub fn generic_object(comptime T: type) type {
    return struct {
        pub fn get_object(self: *T) *GameObject {
            return &self.game_object;
        }
        pub fn destroy(self: *T, alloc: Allocator) void {
            alloc.destroy(self);
        }
    };
}
pub const noDraw = noUpdate;
pub fn noShot(ctx: *anyopaque, strength: u8) void {
    _ = ctx;
    _ = strength;
}
pub fn debug_draw_hitbox(self: *GameObject) void {
    tic80.rectb(self.x + self.hit_x - self.game_state.camera_x, self.y + self.hit_y - self.game_state.camera_y, self.hit_w, self.hit_h, 1);
}
pub const vtable: VTable = .{ .get_object = @ptrCast(&identity), .ptr_update = &noUpdate, .ptr_draw = &noDraw, .destroy = &noDestroy };
