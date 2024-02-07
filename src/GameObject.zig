const GameObject = @This();

const tic80 = @import("tic80.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const GameState = @import("GameState.zig");

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
    pub fn destroy(self: *const IsGameObject, alloc: Allocator) void {
        self.table.destroy(self.ptr, alloc);
    }
};
pub const VTable = struct {
    get_object: *const fn (self: *anyopaque) *GameObject,
    ptr_update: *const fn (self: *anyopaque) void,
    ptr_draw: *const fn (self: *anyopaque) void,
    destroy: *const fn (self: *anyopaque, allocator: std.mem.Allocator) void,
    pub fn move_x(self: *const VTable, item: *anyopaque, x: f32, on_collide: ?*const fn (*anyopaque, moved: i32, target: i32) bool) bool {
        var gobj = self.get_object(item);
        gobj.remainder_x += x;
        var mx: i32 = @intFromFloat(@floor(gobj.remainder_x + 0.5));
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
        var my: i32 = @intFromFloat(@floor(gobj.remainder_y + 0.5));
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

speed_x: f32 = 0,
speed_y: f32 = 0,
remainder_x: f32 = 0,
remainder_y: f32 = 0,
hit_x: i32 = 0,
hit_y: i32 = 0,
hit_w: u31 = 8,
hit_h: u31 = 8,
hazard: HazardType = .none,
solid: bool = false,
facing: i2 = 0,
x: i32,
y: i32,
id: i64,
destroyed: bool = false,
game_state: *GameState,
destructable: bool = false,
// will never be freed on cleanup
persistent: bool = false,

pub fn overlaps(self: *GameObject, btable: IsGameObject, ox: i32, oy: i32) bool {
    const b = btable.obj();
    if (self == b)
        return false;
    return ox + self.x + self.hit_x + self.hit_w > b.x + b.hit_x and
        oy + self.y + self.hit_y + self.hit_h > b.y + b.hit_y and
        ox + self.x + self.hit_x < b.x + b.hit_x + b.hit_w and
        oy + self.y + self.hit_y < b.y + b.hit_y + b.hit_h;
}
pub fn contains(self: *GameObject, px: u64, py: u64) bool {
    return px >= self.x + self.hit_x and
        px < self.x + self.hit_x + self.hit_w and
        py >= self.y + self.hit_y and
        py < self.y + self.hit_y + self.hit_h;
}
pub fn check_solid(self: *GameObject, ox: i32, oy: i32) bool {
    var i: i32 = @divFloor(ox + self.x + self.hit_x, 8);
    // in 4k?
    const imax = @divFloor(ox + self.x + self.hit_x + @as(i32, self.hit_w) - 1, 8);
    const jmin = @divFloor(oy + self.y + self.hit_y, 8);
    const jmax = @divFloor(oy + self.y + self.hit_y + @as(i32, self.hit_h) - 1, 8);
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

pub fn create(state: *GameState, x: i32, y: i32) GameObject {
    return .{ .game_state = state, .x = x, .y = y, .id = @divFloor(x, 8) + @divFloor(y, 8) * 128 };
}

fn identity(self: *GameObject) *GameObject {
    return self;
}
pub fn update(self: *GameObject) void {
    _ = self;
}
pub fn draw(self: *GameObject) void {
    _ = self;
}
fn destroy(self: *GameObject, alloc: Allocator) void {
    _ = self;
    _ = alloc;
}

pub fn debug_draw_hitbox(self: *GameObject) void {
    tic80.rectb(self.x + self.hit_x, self.y + self.hit_y, self.hit_w, self.hit_h, 1);
}
pub const vtable: VTable = .{ .get_object = @ptrCast(&identity), .ptr_update = @ptrCast(&update), .ptr_draw = @ptrCast(&draw), .destroy = @ptrCast(&destroy) };
