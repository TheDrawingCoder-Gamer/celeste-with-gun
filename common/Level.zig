const Level = @This();
const math = @import("math.zig");

pub const CamMode = enum { locked, follow_x, follow_y, free_follow };
pub const Entity = struct {
    pub const Kind = union(enum) {
        const Switch = struct { kind: u8, shootable: bool, touchable: bool };
        const Door = struct { kind: u8, target: math.Point };
        const Traffic = struct { target: math.Point };
        const Destructible = struct { shoot_only: bool };
        const Spike = struct { direction: math.CardinalDir };
        switch_coin: Switch,
        switch_door: Door,
        traffic_block: Traffic,
        destructible: Destructible,
        crumble: void,
        player_start: bool,
        spike: Spike,
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
