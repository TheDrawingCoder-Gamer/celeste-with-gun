const SwitchDoor = @This();

const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const tic = @import("tic80.zig");
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
width: u16,
height: u16,
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
    w: u16 = 1,
    h: u16 = 1,
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
    // sfx...
}

fn update(ctx: *anyopaque) void {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    if (self.active and self.t_progress < 20) {
        self.t_progress += 1;
        const progress: f32 = @as(f32, @floatFromInt(self.t_progress)) / 20;
        const x: i32 = @intFromFloat(types.lerp(@floatFromInt(self.start_x), @floatFromInt(self.target.x), progress));
        const y: i32 = @intFromFloat(types.lerp(@floatFromInt(self.start_y), @floatFromInt(self.target.y), progress));
        Solid.move_to(.{ .ptr = self, .table = table }, x, y);
    }
}
fn draw(ctx: *anyopaque) void {
    const self: *SwitchDoor = @alignCast(@ptrCast(ctx));
    const x1: i32 = self.game_object.x - self.game_object.game_state.camera_x;
    const y1: i32 = self.game_object.y - self.game_object.game_state.camera_y;
    const w = self.width * 8;
    const h = self.height * 8;
    tic.rect(x1, y1, w, h, 14);
    tic.rectb(x1, y1, w, h, 13);
    tdraw.set1bpp();
    tic.PALETTE_MAP.color1 = 11;
    defer tdraw.set4bpp();
    defer tdraw.reset_pallete();
    tic.spr(1540, x1 + (w / 2) - 3, y1 + (h / 2) - 3, .{ .transparent = &.{0} });
}
