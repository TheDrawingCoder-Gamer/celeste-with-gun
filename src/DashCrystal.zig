const DashCrystal = @This();

const std = @import("std");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const tic = @import("common").tic;
const tdraw = @import("draw.zig");

const vtable: GameObject.VTable = .{ .ptr_update = @ptrCast(&update), .ptr_draw = @ptrCast(&draw), .can_touch = &GameObject.yesCanTouch, .get_object = @ptrCast(&dash_obj.get_object), .destroy = @ptrCast(&dash_obj.destroy), .touch = @ptrCast(&touch) };
game_object: GameObject,
dashes: u8,
use_timer: u8 = 0,
const dash_obj = GameObject.generic_object(DashCrystal);
pub fn create(state: *GameState, x: i32, y: i32, dash_n: u8) !*DashCrystal {
    var obj = GameObject.create(state, x, y);
    obj.touchable = true;

    const self = try state.allocator.create(DashCrystal);
    self.* = .{ .game_object = obj, .dashes = dash_n };

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn update(self: *DashCrystal) void {
    if (self.use_timer > 0) {
        self.use_timer -= 1;
    }
}

fn touch(self: *DashCrystal, player: *Player) void {
    if (self.use_timer != 0) return;
    // TODO: test for midair shot count?
    if (player.dashes < self.dashes) {
        self.use_timer = 120;
        player.refill_dashes();
        player.dashes = self.dashes;
    }
}
fn dash_crystal_palette(dashes: u8) void {
    const dash_pal: struct { u4, u4 } = switch (dashes) {
        1 => .{ 1, 2 },
        2 => .{ 6, 5 },
        3 => .{ 13, 14 },
        4 => .{ 4, 3 },
        else => .{ 2, 3 },
    };
    tic.PALETTE_MAP.color1 = 12;
    tic.PALETTE_MAP.color2 = dash_pal[0];
    tic.PALETTE_MAP.color3 = dash_pal[1];
}
fn dash_sprite(exists: bool, dashes: u8) i32 {
    const res: struct { i32, i32 } = switch (dashes) {
        1 => .{ 805, 806 },
        2 => .{ 807, 808 },
        3 => .{ 809, 810 },
        4 => .{ 811, 812 },
        else => .{ 773, 774 },
    };
    return if (exists) res[0] else res[1];
}
fn draw(self: *DashCrystal) void {
    tdraw.set2bpp();
    defer tdraw.set4bpp();
    dash_crystal_palette(self.dashes);
    defer tdraw.reset_pallete();
    const id: i32 = dash_sprite(self.use_timer == 0, self.dashes);
    self.game_object.game_state.draw_spr(id, self.game_object.x, self.game_object.y, .{ .transparent = &.{0} });
}
