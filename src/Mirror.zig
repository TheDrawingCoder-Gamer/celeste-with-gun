const Mirror = @This();

const std = @import("std");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const sheets = @import("sheets.zig");
const tic = @import("common").tic;
const types = @import("types.zig");
const CardinalDir = @import("common").math.CardinalDir;

const vtable: GameObject.VTable = .{ .ptr_draw = &draw, .get_object = &get_object, .ptr_update = &GameObject.noUpdate, .destroy = @ptrCast(&destroy) };

direction: CardinalDir,
game_object: GameObject,

fn draw(ctx: *anyopaque) void {
    const self: *Mirror = @alignCast(@ptrCast(ctx));
    const rot = self.get_rot();
    self.game_object.game_state.draw_sprite(sheets.slope.items[1], self.game_object.x, self.game_object.y, .{ .rotate = rot });
}

fn get_rot(self: *const Mirror) tic.Rotate {
    return switch (self.direction) {
        .up => .no,
        .right => .by90,
        .down => .by180,
        .left => .by270,
    };
}

fn destroy(self: *Mirror, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

pub fn create(allocator: std.mem.Allocator, state: *GameState, x: i32, y: i32, dir: CardinalDir) !*Mirror {
    var obj = GameObject.create(state, x, y);
    obj.hit_x = 0;
    obj.hit_y = 0;
    obj.hit_w = 8;
    obj.hit_h = 8;
    // ???
    obj.hurtbox = .{ .x = 0, .y = 0, .w = 8, .h = 8 };
    obj.special_type = .mirror;
    const self = try allocator.create(Mirror);
    self.game_object = obj;
    self.direction = dir;

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *Mirror = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}
