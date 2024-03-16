const AmmoCrystal = @This();

const std = @import("std");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const Player = @import("Player.zig");
const tic = @import("common").tic;
const tdraw = @import("draw.zig");
const sheets = @import("sheets.zig");
const Sprite = @import("common").Spritesheet.Sprite;

const vtable: GameObject.VTable = .{
    .ptr_update = @ptrCast(&update),
    .ptr_draw = @ptrCast(&draw),
    .can_touch = &GameObject.yesCanTouch,
    .get_object = @ptrCast(&ammo_obj.get_object),
    .destroy = @ptrCast(&ammo_obj.destroy),
    .touch = @ptrCast(&touch),
};
game_object: GameObject,
use_timer: u8 = 0,
const ammo_obj = GameObject.generic_object(AmmoCrystal);
pub fn create(state: *GameState, x: i32, y: i32) !*AmmoCrystal {
    var obj = GameObject.create(state, x, y);
    obj.touchable = true;

    const self = try state.allocator.create(AmmoCrystal);
    self.* = .{ .game_object = obj };

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn update(self: *AmmoCrystal) void {
    if (self.use_timer > 0) {
        self.use_timer -= 1;
    }
}

fn touch(self: *AmmoCrystal, player: *Player) void {
    if (self.use_timer != 0) return;
    if (player.midair_shot_count < Player.MAX_MIDAIR_SHOT) {
        player.midair_shot_count = Player.MAX_MIDAIR_SHOT;
        self.use_timer = 120;
    }
}
fn dash_sprite(exists: bool) Sprite {
    return sheets.ammo_reload.items[if (exists) 0 else 1];
}
fn draw(self: *AmmoCrystal) void {
    const spr = dash_sprite(self.use_timer == 0);
    self.game_object.game_state.draw_sprite(spr, self.game_object.x, self.game_object.y, .{});
}
