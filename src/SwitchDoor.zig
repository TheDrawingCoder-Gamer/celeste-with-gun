const SwitchDoor = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const tic = @import("common").tic;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const tdraw = @import("draw.zig");
const Solid = @import("Solid.zig");

const table: GameObject.VTable = .{
    .get_object = &get_object,
    .destroy = &destroy,
    .ptr_draw = &draw,
    .ptr_update = &update,
};
game_object: GameObject,
kind: u8 = 0,
width: u31,
height: u31,
target: types.Point,
active: bool = false,
t_progress: u8 = 0,
start_x: i32,
start_y: i32,

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}

fn destroy(ctx: *anyopaque, allocator: Allocator) void {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    allocator.destroy(self);
}

const DoorArgs = struct {
    kind: u8 = 0,
    w: u31 = 1,
    h: u31 = 1,
    target: types.Point,
};
pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, args: DoorArgs) !*SwitchDoor {
    var obj = GameObject.create(state, x, y);
    obj.solid = true;
    obj.hit_x = 0;
    obj.hit_y = 0;
    obj.hit_w = 8 * args.w;
    obj.hit_h = 8 * args.h;
    obj.special_type = .sheild_door;

    const self = try allocator.create(SwitchDoor);
    self.game_object = obj;
    self.kind = args.kind;
    self.width = args.w;
    self.height = args.h;
    self.target = args.target;
    self.start_x = x;
    self.start_y = y;
    self.active = false;

    const node = try state.wrap_node(.{ .ptr = self, .table = table });
    state.objects.append(node);

    return self;
}

pub fn activated(self: *SwitchDoor) void {
    self.active = true;
    self.t_progress = 0;
    self.game_object.speed_x = @as(f32, @floatFromInt(self.target.x - self.start_x)) / 20.0;
    self.game_object.speed_y = @as(f32, @floatFromInt(self.target.y - self.start_y)) / 20.0;
    // sfx...
}

fn update(ctx: *anyopaque) void {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    if (self.active and self.t_progress < 20) {
        self.t_progress += 1;
        const progress: f32 = @as(f32, @floatFromInt(self.t_progress)) / 20;
        const x = types.lerp(@floatFromInt(self.start_x), @floatFromInt(self.target.x), progress);
        const y = types.lerp(@floatFromInt(self.start_y), @floatFromInt(self.target.y), progress);
        Solid.move_to_point_once(.{ .ptr = self, .table = table }, .{ .x = x, .y = y });
    }
}
fn draw(ctx: *anyopaque) void {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    const x1: i32 = self.game_object.x - self.game_object.game_state.camera_x;
    const y1: i32 = self.game_object.y - self.game_object.game_state.camera_y;
    const w = self.width * 8;
    const h = self.height * 8;
    tic.rect(x1, y1, w, h, 8);
    tic.rectb(x1, y1, w, h, 9);
    // corners
    tic.spr(467, x1, y1, .{ .transparent = &.{0} });
    tic.spr(467, x1 + w - 8, y1, .{ .transparent = &.{0}, .rotate = .by90 });
    tic.spr(467, x1 + w - 8, y1 + h - 8, .{ .transparent = &.{0}, .rotate = .by180 });
    tic.spr(467, x1, y1 + h - 8, .{ .transparent = &.{0}, .rotate = .by270 });
    tdraw.set1bpp();
    tic.PALETTE_MAP.color1 = 11;
    defer tdraw.set4bpp();
    defer tdraw.reset_pallete();
    const spr_x = x1 +
        if (@mod(self.width, 2) != 0) @divFloor(self.width, 2) * 8 else self.width * 4 - 4;
    const spr_y = y1 +
        if (@mod(self.height, 2) != 0) @divFloor(self.height, 2) * 8 else self.height * 4 - 4;
    tic.spr(1540, spr_x, spr_y, .{ .transparent = &.{0} });
}
