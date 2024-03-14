const DashCrystal = @This();

const std = @import("std");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const tic = @import("common").tic;
const tdraw = @import("draw.zig");
const sheets = @import("sheets.zig");
const Sprite = @import("common").Spritesheet.Sprite;

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
fn dash_sprite(exists: bool, dashes: u8) Sprite {
    const data: u8 = blk: {
        const res = dashes * 2;
        if (res >= 10) break :blk if (exists) 0 else 1;
        break :blk if (exists) res else res + 1;
    };
    return sheets.dash_crystal.items[data];
}
fn draw(self: *DashCrystal) void {
    tdraw.set2bpp();
    defer tdraw.set4bpp();
    const spr = dash_sprite(self.use_timer == 0, self.dashes);
    self.game_object.game_state.draw_sprite(spr, self.game_object.x, self.game_object.y, .{});
}
