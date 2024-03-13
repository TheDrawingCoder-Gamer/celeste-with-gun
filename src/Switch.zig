const Switch = @This();

const tic = @import("common").tic;
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const std = @import("std");
const Player = @import("Player.zig");
const Allocator = std.mem.Allocator;
const SwitchDoor = @import("SwitchDoor.zig");
const tdraw = @import("draw.zig");
const sheets = @import("sheets.zig");

game_object: GameObject,
active: bool = false,
kind: u8 = 0,
w: u31,
h: u31,

const vtable: GameObject.VTable = .{ .destroy = &destroy, .get_object = &get_object, .touch = &touch, .can_touch = &can_touch, .shot = &shot, .ptr_draw = &draw };
const CreateArgs = struct {
    kind: u8 = 0,
    is_gun: bool = true,
    is_touch: bool = false,
};
pub fn create(allocator: Allocator, state: *GameState, x: i32, y: i32, w: u31, h: u31, args: CreateArgs) !*Switch {
    var obj = GameObject.create(state, x, y);
    obj.special_type = .sheild_toggle;
    obj.shootable = args.is_gun;
    obj.touchable = args.is_touch;
    obj.hit_x = -2;
    obj.hit_y = -2;
    obj.hit_w = w + 2;
    obj.hit_h = h + 2;

    const self = try allocator.create(Switch);
    self.* = .{ .game_object = obj, .active = false, .kind = args.kind, .w = w, .h = h };

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

fn shot(ctx: *anyopaque, strength: u8) void {
    if (strength <= 10) return;
    const self: *Switch = @alignCast(@ptrCast(ctx));

    self.activated();
}

fn draw(ctx: *anyopaque) void {
    const self: *Switch = @alignCast(@ptrCast(ctx));
    const x = self.game_object.x - self.game_object.game_state.camera_x;
    const y = self.game_object.y - self.game_object.game_state.camera_y;
    const hw = self.w / 2;
    const hh = self.h / 2;
    tic.ellib(x + hw, y + hh, hw, hh, if (self.active) 2 else 10);
    defer tdraw.set4bpp();
    defer tdraw.reset_pallete();
    tdraw.set1bpp();
    tic.PALETTE_MAP.color1 = 15;

    if (self.game_object.touchable) {
        tic.PALETTE_MAP.color1 = if (self.active) 2 else 10;
        self.game_object.game_state.draw_spr(sheets.shield_icons.items[0], self.game_object.x + hw - 4, self.game_object.y + hh - 4, .{ .transparent = &.{0} });
    }

    if (self.game_object.shootable) {
        tic.PALETTE_MAP.color1 = if (self.active) 1 else 2;
        self.game_object.game_state.draw_spr(sheets.shield_icons.items[1], self.game_object.x + hw - 4, self.game_object.y + hh - 4, .{ .transparent = &.{0} });
    }
}
