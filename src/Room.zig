const types = @import("types.zig");

pub const CamMode = enum(u8) {
    locked,
    follow_x,
    follow_y,
    free_follow,
};

pub const Entity = struct {
    pub const Kind = union(enum) {
        const SwitchBlock = struct {
            kind: u8,
            shootable: bool,
            touchable: bool,
        };
        const Door = struct {
            kind: u8,
            w: u16,
            h: u16,
            target: types.Point,
        };
        const Traffic = struct {
            w: u16,
            h: u16,
            target: types.Point,
        };
        switch_block: SwitchBlock,
        switch_door: Door,
        traffic_block: Traffic,
    };
    x: i32,
    y: i32,
    kind: Kind,
};
pub const Room = struct {
    box: types.Box,
    cam_mode: CamMode = .locked,
    death_bottom: bool = true,
    entities: ?[]const Entity = null,
};
