const Level = @This();
const math = @import("math.zig");

pub const Tile = struct { pos: math.Point, tile: u8 };
pub const CompressedTile = packed struct(u16) { fg: u8, bg: u8 };
// bg_tiles are in the bg obv
pub const CompressedMap = struct { levels: []Level, tiles: []const Tile, bg_tiles: []const Tile = &.{} };
pub const CamMode = enum(u8) { locked, follow_x, follow_y, free_follow };
pub const Entity = struct {
    pub const Kind = union(enum) {
        const Switch = struct { kind: u8, shootable: bool, touchable: bool };
        const Door = struct { kind: u8, target: math.Point };
        const Traffic = struct { target: math.Point, speed: f32 };
        const Destructible = struct { shoot_only: bool };
        const Spike = struct { direction: math.CardinalDir };
        switch_coin: Switch,
        switch_door: Door,
        traffic_block: Traffic,
        destructible: Destructible,
        crumble: void,
        player_start: bool,
        spike: Spike,
        dash_crystal: u8,
        checkpoint: void,
        ammo_crystal,
    };
    x: i32,
    y: i32,
    w: u31,
    h: u31,
    kind: Kind,
};
x: i32,
y: i32,
width: u31,
height: u31,
cam_mode: CamMode,
death_bottom: bool,
entities: []const Entity
