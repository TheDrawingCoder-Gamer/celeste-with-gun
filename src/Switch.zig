const Switch = @This();

const tic = @import("common").tic;
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Player = @import("Player.zig");
const Allocator = std.mem.Allocator;
const SwitchDoor = @import("SwitchDoor.zig");
const tdraw = @import("draw.zig");

game_object: GameObject,
active: bool = false,
kind: u8 = 0,

const vtable: GameObject.VTable = .{ .destroy = &destroy, .get_object = &get_object, .touch = &touch, .can_touch = &can_touch, .shot = &shot, .ptr_draw = &draw };
const CreateArgs = struct {
    kind: u8 = 0,
    is_gun: bool = true,
    is_touch: bool = false,
};
pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, args: CreateArgs) !*Switch {
    var obj = GameObject.create(state, x, y);
    obj.special_type = .sheild_toggle;
    obj.shootable = args.is_gun;
    obj.touchable = args.is_touch;

    const self = try allocator.create(Switch);
    self.game_object = obj;
    self.active = false;
    self.kind = args.kind;

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn destroy(ctx: *anyopaque, allocator: Allocator) void {
    const self: *Switch = @alignCast(@ptrCast(ctx));
    allocator.destroy(self);
}

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *Switch = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}

fn activated(self: *Switch) void {
    if (self.active) return;
    self.active = true;
    {
        var it = self.game_object.game_state.objects.first;
        while (it) |node| : (it = node.next) {
            const d = node.data;
            switch (d.obj().special_type) {
                .sheild_toggle => {
                    const other: *Switch = @alignCast(@ptrCast(d.ptr));
                    if (other.kind == self.kind and !other.active)
                        return;
                },
                else => {},
            }
        }
    }
    {
        var it = self.game_object.game_state.objects.first;
        while (it) |node| : (it = node.next) {
            const d = node.data;
            const obj = d.obj();
            switch (obj.special_type) {
                .sheild_door => {
                    const other: *SwitchDoor = @alignCast(@ptrCast(d.ptr));
                    if (!other.active and other.kind == self.kind) {
                        other.activated();
                    }
                },
                else => {},
            }
        }
    }
}
// if we are getting called we consented to touching upon creation
fn can_touch(ctx: *anyopaque, player: *Player) bool {
    _ = player;
    const self: *Switch = @alignCast(@ptrCast(ctx));
    return !self.active;
}

fn touch(ctx: *anyopaque, player: *Player) void {
    _ = player;
    const self: *Switch = @alignCast(@ptrCast(ctx));

    self.activated();
}

fn shot(ctx: *anyopaque) void {
    const self: *Switch = @alignCast(@ptrCast(ctx));

    self.activated();
}

fn draw(ctx: *anyopaque) void {
    const self: *Switch = @alignCast(@ptrCast(ctx));

    defer tdraw.set4bpp();
    defer tdraw.reset_pallete();
    tdraw.set1bpp();
    tic.PALETTE_MAP.color1 = 15;
    self.game_object.game_state.draw_spr(1539, self.game_object.x, self.game_object.y, .{ .transparent = &.{0} });

    if (self.game_object.touchable) {
        tic.PALETTE_MAP.color1 = if (self.active) 2 else 10;
        self.game_object.game_state.draw_spr(1540, self.game_object.x, self.game_object.y, .{ .transparent = &.{0} });
    }

    if (self.game_object.shootable) {
        tic.PALETTE_MAP.color1 = if (self.active) 1 else 2;
        self.game_object.game_state.draw_spr(1542, self.game_object.x, self.game_object.y, .{ .transparent = &.{0} });
    }

    tic.PALETTE_MAP.color1 = if (self.active) 2 else 10;
    self.game_object.game_state.draw_spr(1543, self.game_object.x, self.game_object.y, .{ .transparent = &.{0} });
}
