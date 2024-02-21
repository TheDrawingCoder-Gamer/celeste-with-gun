const types = @This();

const std = @import("std");
const tic = @import("tic80.zig");

pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,
    pub fn add(self: Point, other: Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
    pub fn times(self: Point, scalar: i32) Point {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }
    pub fn as_float(self: Point) PointF {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    }
};
pub const PointF = struct {
    x: f32 = 0,
    y: f32 = 0,
    pub fn add(self: PointF, other: PointF) PointF {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
    pub fn minus(self: PointF, other: PointF) PointF {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }
    pub fn times(self: PointF, scalar: f32) PointF {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }
    pub fn as_int(self: PointF) Point {
        return .{ .x = @intFromFloat(self.x), .y = @intFromFloat(self.y) };
    }
    pub fn min(left: PointF, right: PointF) PointF {
        return .{ .x = @min(left.x, right.x), .y = @min(left.y, right.y) };
    }
    pub fn max(left: PointF, right: PointF) PointF {
        return .{ .x = @max(left.x, right.x), .y = @max(left.y, right.y) };
    }
    pub fn from_radians(angle: f32) PointF {
        const x = @cos(angle);
        const y = -@sin(angle);
        return .{ .x = x, .y = y };
    }
    pub fn normalized(self: PointF) PointF {
        const len = self.length();
        // panics (?) on divide by 0
        return .{ .x = self.x / len, .y = self.y / len };
    }
    pub fn to_radians(self: PointF) f32 {
        return std.math.atan2(-self.y, self.x);
    }
    pub fn length_squared(self: PointF) f32 {
        return std.math.pow(f32, self.x, 2) + std.math.pow(f32, self.y, 2);
    }
    pub fn length(self: PointF) f32 {
        return std.math.sqrt(self.length_squared());
    }
    pub fn distance_squared(self: PointF, other: PointF) f32 {
        return std.math.pow(f32, self.x - other.x, 2) + std.math.pow(f32, self.y - other.y, 2);
    }
    pub fn distance(self: PointF, other: PointF) f32 {
        return std.math.sqrt(self.distance_squared(other));
    }

    pub fn dot(self: PointF, other: PointF) f32 {
        return (self.x * other.x) + (self.y * other.y);
    }

    pub fn with_x(self: PointF, x: f32) PointF {
        return .{ .x = x, .y = self.y };
    }
    pub fn with_y(self: PointF, y: f32) PointF {
        return .{ .x = self.x, .y = y };
    }

    pub fn approach(self: PointF, speed_x: f32, speed_y: f32, target: PointF) PointF {
        return .{ .x = types.approach(self.x, target.x, speed_x), .y = types.approach(self.y, target.y, speed_y) };
    }

    pub fn lerp(left: PointF, right: PointF, t: f32) PointF {
        return .{ .x = types.lerp(left.x, right.x, t), .y = types.lerp(left.y, right.y, t) };
    }

    pub fn cross(self: PointF, other: PointF) f32 {
        return (self.x * other.y) - (self.y * other.x);
    }

    pub fn trunc(self: PointF) PointF {
        return .{ .x = @trunc(self.x), .y = @trunc(self.y) };
    }
    pub fn floor(self: PointF) PointF {
        return .{ .x = @floor(self.x), .y = @floor(self.y) };
    }
};

pub fn approach(x: anytype, target: anytype, max_delta: anytype) @TypeOf(x, target, max_delta) {
    return if (x < target) @min(x + max_delta, target) else @max(x - max_delta, target);
}

pub fn sine_in_out(t: f32) f32 {
    return -(std.math.cos(std.math.pi * t) - 1) / 2;
}
pub fn lerp(min: f32, max: f32, t: f32) f32 {
    return (1 - t) * min + t * max;
}

pub fn abs(x: anytype) @TypeOf(x) {
    return x * std.math.sign(x);
}
pub const Box = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    pub fn overlapping(self: Box, other: Box) bool {
        const sx1 = self.x;
        const sy1 = self.y;
        const sx2 = self.x + self.w;
        const sy2 = self.y + self.h;

        const ox1 = other.x;
        const oy1 = other.y;
        const ox2 = other.x + other.w;
        const oy2 = other.y + other.h;

        return sx2 > ox1 and sy2 > oy1 and sx1 < ox2 and sy1 < oy2;
    }
    pub fn contains(self: Box, x: i32, y: i32) bool {
        return x >= self.x and
            x < self.x + self.w and
            y >= self.y and
            y < self.y + self.h;
    }
    pub fn aabb(x1: i32, y1: i32, x2: i32, y2: i32) Box {
        const minx = @min(x1, x2);
        const miny = @min(y1, y2);
        const maxx = @max(x1, x2);
        const maxy = @max(y1, y2);
        return aabb_unchecked(minx, miny, maxx, maxy);
    }
    pub fn aabb_unchecked(x1: i32, y1: i32, x2: i32, y2: i32) Box {
        return .{ .x = x1, .y = y1, .w = x2 - x1, .h = y2 - y1 };
    }
    pub fn inflate(self: Box, n: i32) Box {
        return .{ .x = self.x - n, .y = self.y - n, .w = self.w + n, .h = self.h + n };
    }

    pub fn segments(self: Box) [4]LineSegment {
        return .{
            .{ .start = self.top_right().as_float(), .end = self.bottom_right().as_float() },
            .{ .start = self.top_left().as_float(), .end = self.top_right().as_float() },
            .{ .start = self.bottom_left().as_float(), .end = self.top_left().as_float() },
            .{ .start = self.bottom_right().as_float(), .end = self.bottom_left().as_float() },
        };
    }
    pub fn angled_lines(self: Box) [4]AngledLine {
        var lines: [4]AngledLine = undefined;
        for (self.segments(), 0..) |segment, i| {
            lines[i].line = segment;
            lines[i].angle = @as(f32, @floatFromInt(i)) * (std.math.pi / 2.0);
        }
        return lines;
    }
    pub fn top_left(self: Box) Point {
        return .{ .x = self.x, .y = self.y };
    }
    pub fn top_mid(self: Box) PointF {
        return self.top_left().as_float().add(.{ .x = @as(f32, @floatFromInt(self.w - 1)) / 2, .y = 0 });
    }
    pub fn top_right(self: Box) Point {
        return .{ .x = self.x + self.w - 1, .y = self.y };
    }
    pub fn bottom_left(self: Box) Point {
        return .{ .x = self.x, .y = self.y + self.h - 1 };
    }
    pub fn bottom_mid(self: Box) PointF {
        return self.bottom_left().as_float().add(.{ .x = @as(f32, @floatFromInt(self.w - 1)) / 2, .y = 0 });
    }
    pub fn bottom_right(self: Box) Point {
        return .{ .x = self.x + self.w - 1, .y = self.y + self.h - 1 };
    }
    pub fn mid_left(self: Box) PointF {
        return self.top_left().as_float().add(.{ .x = 0, .y = @as(f32, @floatFromInt(self.h - 1)) / 2 });
    }
    pub fn mid_right(self: Box) PointF {
        return self.top_right().as_float().add(.{ .x = 0, .y = @as(f32, @floatFromInt(self.h - 1)) / 2 });
    }
    pub fn midpoint(self: Box) PointF {
        return self.mid_left().add(.{ .x = @as(f32, @floatFromInt(self.w - 1)) / 2 });
    }
};

pub const Direction = enum(u2) { up = 0, right = 1, down = 2, left = 3 };

pub const LineSegment = struct {
    start: PointF,
    end: PointF,
    pub fn intersects(p_line: LineSegment, q_line: LineSegment) ?PointF {
        const p = p_line.start;
        const q = q_line.start;
        const r = p_line.end.minus(p);
        const s = q_line.end.minus(q);

        const r_x_s = r.cross(s);
        // either colinear or paralell. i don't really care LOL
        if (abs(r_x_s) < 0.00001)
            return null;
        // Cross product is anticommutative
        const qps = q.minus(p).cross(s);
        const qpr = q.minus(p).cross(r);

        const t = qps / r_x_s;
        const u = qpr / r_x_s;

        if (t >= 0 and t <= 1 and u >= 0 and u <= 1) {
            return p.add(r.times(t));
        }

        return null;
    }
    pub fn angle(self: LineSegment) f32 {
        self.end.minus(self.start).to_radians();
    }
    pub fn debug_draw(self: LineSegment, cam: types.PointF, color: u4) void {
        // vbank to force overlay
        _ = tic.vbank(1);
        tic.line(self.start.x - cam.x, self.start.y - cam.y, self.end.x - cam.x, self.end.y - cam.y, color);
        _ = tic.vbank(0);
    }
};

test "line intersects" {
    const segment_1: LineSegment = .{ .start = .{ .x = 0, .y = 0 }, .end = .{ .x = 0, .y = -1 } };
    const segment_2: LineSegment = .{ .start = .{ .x = 1, .y = -0.5 }, .end = .{ .x = -1, .y = -0.5 } };
    const res: ?PointF = .{ .x = 0, .y = -0.5 };
    try std.testing.expectEqual(res, segment_1.intersects(segment_2));
}

pub const AngledLine = struct {
    line: LineSegment,
    angle: f32,
    pub fn debug_draw(self: AngledLine, cam: types.PointF, color: u4, angle_color: u4) void {
        self.line.debug_draw(cam, color);
        const diff = self.line.end.minus(self.line.start);
        const midpoint = self.line.start.add(diff.times(0.5));
        const point = PointF.from_radians(self.angle);
        _ = tic.vbank(1);
        const sx = midpoint.x - cam.x;
        const sy = midpoint.y - cam.y;
        tic.line(sx, sy, sx + point.x * 4, sy + point.y * 4, angle_color);
        _ = tic.vbank(0);
    }
};

pub const Ray = struct { start: Point, angle: f32 };

const tau = std.math.tau;
const pi = std.math.pi;

pub fn normalize_angle(theta: f32) f32 {
    var angle = @mod(theta, tau);
    if (angle > pi)
        angle -= tau;
    return angle;
}

pub fn angle_difference(left: f32, right: f32) f32 {
    return normalize_angle(normalize_angle(left) - normalize_angle(right));
}

// how aligned two angles are. 1 is equavilant, -1 is literal opposites.
pub fn angle_alignment(left: f32, right: f32) f32 {
    return @cos(angle_difference(left, right));
}
