const TrafficBlock = @This();

const tic = @import("common").tic;
const Player = @import("Player.zig");
const GameObject = @import("GameObject.zig");
const GameState = @import("GameState.zig");
const types = @import("types.zig");
const std = @import("std");
const Solid = @import("Solid.zig");
const tdraw = @import("draw.zig");
const sheets = @import("sheets.zig");

const vtable: GameObject.VTable = .{ .destroy = &destroy, .can_touch = &can_touch, .touch = &touch, .ptr_draw = &draw, .ptr_update = &update, .get_object = &get_object };

const State = enum { idle, advancing, retreating, stalled };
game_object: GameObject,
state: State = .idle,
t_progress: u8 = 0,
start: types.Point,
target: types.Point,
width: u31,
height: u31,
last_touched: u64 = 0,
lerp: f32 = 0,
gear_frame: f32 = 0,
audio_frame: i32 = 0,
speed: f32 = 1.0,

pub fn create(state: *GameState, x: i32, y: i32, w: u31, h: u31, target: types.Point, speed: f32) !*TrafficBlock {
    var obj = GameObject.create(state, x, y);
    obj.hit_w = 8 * w;
    obj.hit_h = 8 * h;
    obj.solid = true;
    obj.touchable = true;

    const self = try state.allocator.create(TrafficBlock);
    self.* = .{ .start = .{ .x = x, .y = y }, .target = target, .game_object = obj, .width = w, .height = h, .speed = speed };

    const node = try state.wrap_node(.{ .ptr = self, .table = vtable });
    state.objects.append(node);

    return self;
}

fn destroy(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));

    tic.sfx(-1, .{});
    allocator.destroy(self);
}

fn can_touch(ctx: *anyopaque, player: *Player) bool {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));
    if (self.game_object.game_state.time <= self.last_touched + 1) {
        return false;
    }
    if (player.game_object.overlaps_box(0, 1, self.game_object.world_hitbox())) {
        self.last_touched = self.game_object.game_state.time;
        return self.state == .idle;
    }
    return false;
}

fn touch(ctx: *anyopaque, player: *Player) void {
    _ = player;
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));

    self.last_touched = self.game_object.game_state.time;
    self.start_advance();
}

fn start_advance(self: *TrafficBlock) void {
    self.state = .advancing;
    const velocity = self.target.add(self.start.times(-1)).as_float().normalized().times(5);
    self.game_object.set_velocity(velocity);
    self.game_object.game_state.voice.play(7, .{ .volume = 6 });
}

fn stall(self: *TrafficBlock) void {
    self.state = .stalled;
    self.t_progress = 30;
    self.game_object.set_velocity(.{ .x = 0, .y = 0 });
}

fn stop(self: *TrafficBlock) void {
    self.state = .idle;
    self.game_object.set_velocity(.{ .x = 0, .y = 0 });
}
fn start_retreat(self: *TrafficBlock) void {
    self.state = .retreating;
    const velocity = self.target.add(self.start.times(-1)).as_float().normalized().times(-1);
    self.game_object.set_velocity(velocity);
}
fn as_table(self: *TrafficBlock) GameObject.IsGameObject {
    return .{ .ptr = self, .table = vtable };
}

fn update(ctx: *anyopaque) void {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));
    if (self.state == .idle)
        return;

    tic.sfx(-1, .{});
    switch (self.state) {
        .idle => {},
        .advancing => {
            self.lerp = types.approach(self.lerp, 1, 1.5 * self.speed / 60.0);
            if (self.lerp == 1.0) {
                self.stall();
            }
            const res = types.PointF.lerp(self.start.as_float(), self.target.as_float(), types.sine_in_out(self.lerp));
            if (self.audio_frame >= 2) {
                tic.sfx(6, .{ .note = 6, .octave = 3, .volume = 6 });
            }
            self.gear_frame -= 0.8;
            Solid.move_to_point_once(self.as_table(), res);
        },
        .retreating => {
            self.lerp = types.approach(self.lerp, 0, 0.3 / 60.0);
            if (self.lerp == 0.0) {
                self.stop();
            } else {
                tic.sfx(6, .{ .note = if (self.gear_frame >= 1.5) 11 else 0, .octave = 1, .volume = 6 });
            }
            const res = types.PointF.lerp(self.start.as_float(), self.target.as_float(), types.sine_in_out(self.lerp));
            self.gear_frame += 0.2;
            Solid.move_to_point_once(self.as_table(), res);
        },
        .stalled => {
            self.t_progress -= 1;
            if (self.t_progress <= 0) {
                self.start_retreat();
            }
        },
    }
    self.gear_frame = @mod(self.gear_frame, 4);
    self.audio_frame += @mod(self.audio_frame + 1, 10);
}

fn draw_chain(self: *TrafficBlock) void {
    const radius = 3.3;
    const gear_size = 3;

    const offset_x = self.target.x - self.start.x;
    const offset_y = self.target.y - self.start.y;
    const offset = types.PointF.normalized(.{ .x = @floatFromInt(offset_x), .y = @floatFromInt(offset_y) });
    const node1 = n: {
        var tmp = offset;
        tmp.x = -offset.y;
        tmp.y = offset.x;
        break :n tmp.times(radius);
    };
    const node2 = n: {
        var tmp = offset;
        tmp.x = offset.y;
        tmp.y = -offset.x;
        break :n tmp.times(radius);
    };
    const node1r = node1.add(.{ .x = radius, .y = radius });
    const node2r = node2.add(.{ .x = radius, .y = radius });
    // ((self.width * 8) / 2) - 4
    const w_offset = (self.width - 1) * 4;
    const h_offset = (self.height - 1) * 4;
    const cam = self.game_object.game_state.camera();
    const start_x = self.start.x - cam.x + w_offset;
    const start_x_f: f32 = @floatFromInt(start_x);
    const start_y = self.start.y - cam.y + h_offset;
    const start_y_f: f32 = @floatFromInt(start_y);
    const end_x = self.target.x - cam.x + w_offset;
    const end_x_f: f32 = @floatFromInt(end_x);
    const end_y = self.target.y - cam.y + h_offset;
    const end_y_f: f32 = @floatFromInt(end_y);

    const line_color = 1;
    tic.line(start_x_f + node1r.x, start_y_f + node1r.y, end_x_f + node1r.x, end_y_f + node1r.y, line_color);
    tic.line(start_x_f + node2r.x, start_y_f + node2r.y, end_x_f + node2r.x, end_y_f + node2r.y, line_color);
    tdraw.arcb(start_x + gear_size, start_y + gear_size, gear_size, node2, node1, line_color);
    tdraw.arcb(end_x + gear_size, end_y + gear_size, gear_size, node1, node2, line_color);

    defer tdraw.set4bpp();
    tdraw.set2bpp();
    tic.PALETTE_MAP.color1 = 8;
    tic.PALETTE_MAP.color2 = 14;

    const gear_frame: usize = @intFromFloat(self.gear_frame);
    const frame = sheets.outergear.items[gear_frame];
    frame.draw(start_x, start_y, .{});

    frame.draw(end_x, end_y, .{});

    tdraw.reset_pallete();
}
fn draw(ctx: *anyopaque) void {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));

    self.draw_chain();
    const x = self.game_object.x - self.game_object.game_state.camera_x;
    const y = self.game_object.y - self.game_object.game_state.camera_y;
    tic.rect(x, y, self.width * 8, self.height * 8, 8);
    tdraw.set2bpp();
    tic.clip(x, y, self.width * 8, self.height * 8);
    {
        const gear_frame: usize = @intFromFloat(self.gear_frame);
        const clockwise_frame = sheets.innergear.items[gear_frame];
        const counter_frame = sheets.innergear.items[3 - gear_frame];

        tic.PALETTE_MAP.color1 = 13;
        tic.PALETTE_MAP.color2 = 14;
        tic.PALETTE_MAP.color3 = 0;
        var i: i32 = 0;
        while (i < self.width) : (i += 1) {
            var j: i32 = 0;
            while (j < self.height) : (j += 1) {
                // xor
                const counter_rotate = (i & 1) != (j & 1);
                const my_frame = if (counter_rotate) counter_frame else clockwise_frame;
                my_frame.draw(x + i * 8, y + j * 8 + 2, .{});
            }
        }
    }
    tic.rectb(x, y + 1, self.width * 8, (self.height * 8) - 1, 14);
    tic.line(@floatFromInt(x), @floatFromInt(y), @floatFromInt(x + self.width * 8), @floatFromInt(y), 13);
    tic.rectb(x + 1, y + 2, self.width * 8 - 2, self.height * 8 - 3, 15);

    // corners
    tdraw.set4bpp();
    tdraw.reset_pallete();
    tic.PALETTE_MAP.color1 = 0;
    sheets.traffic_block.items[1].draw(x, y, .{});
    sheets.traffic_block.items[1].draw(x + (self.width - 1) * 8, y, .{ .flip = .horizontal });

    tdraw.set2bpp();
    tic.PALETTE_MAP.color1 = 15;
    tic.PALETTE_MAP.color2 = 14;
    tic.PALETTE_MAP.color3 = 0;
    sheets.misc.items[1].draw(x + (self.width - 1) * 8, y + (self.height - 1) * 8, .{ .rotate = .by180 });
    sheets.misc.items[1].draw(x, y + (self.height - 1) * 8, .{ .rotate = .by270 });

    var point = x + @divFloor(self.width, 2) * 8;
    // if even
    if (self.width & 1 == 0) {
        point += 4;
    }

    tdraw.reset_pallete();
    tdraw.set4bpp();

    defer tdraw.reset_pallete();
    tic.PALETTE_MAP.color2 = switch (self.state) {
        .idle => 2,
        .advancing => 6,
        .retreating, .stalled => 4,
    };
    sheets.traffic_block.items[0].draw(point, y, .{});
    tic.noclip();
}

fn get_object(ctx: *anyopaque) *GameObject {
    const self: *TrafficBlock = @alignCast(@ptrCast(ctx));
    return &self.game_object;
}
