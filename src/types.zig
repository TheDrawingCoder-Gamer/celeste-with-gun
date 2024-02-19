const std = @import("std");

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
        const angle = self.to_radians() - other.to_radians();
        return self.length() * other.length() * @cos(angle);
    }

    pub fn with_x(self: PointF, x: f32) PointF {
        return .{ .x = x, .y = self.y };
    }
    pub fn with_y(self: PointF, y: f32) PointF {
        return .{ .x = self.x, .y = y };
    }
};

pub fn approach(x: anytype, target: anytype, max_delta: anytype) @TypeOf(x, target, max_delta) {
    return if (x < target) @min(x + max_delta, target) else @max(x - max_delta, target);
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
        const maxx = @max(x1, y1);
        const maxy = @max(x1, y1);
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
            .{ .start = Point.as_float(.{ .x = self.x, .y = self.y }), .end = Point.as_float(.{ .x = self.x + self.w, .y = self.y }) },
            .{ .start = Point.as_float(.{ .x = self.x, .y = self.y }), .end = Point.as_float(.{ .x = self.x, .y = self.y + self.h }) },
            .{ .start = Point.as_float(.{ .x = self.x + self.w, .y = self.y }), .end = Point.as_float(.{ .x = self.x + self.w, .y = self.y + self.h }) },
            .{ .start = Point.as_float(.{ .x = self.x, .y = self.y + self.h }), .end = Point.as_float(.{ .x = self.x + self.w, .y = self.y + self.h }) },
        };
    }
    pub fn top_left(self: Box) Point {
        return .{ .x = self.x, .y = self.y };
    }
    pub fn top_right(self: Box) Point {
        return .{ .x = self.x + self.w, .y = self.y };
    }
    pub fn bottom_left(self: Box) Point {
        return .{ .x = self.x, .y = self.y + self.h };
    }
    pub fn bottom_right(self: Box) Point {
        return .{ .x = self.x + self.w, .y = self.y + self.h };
    }
};

pub const Direction = enum(u2) { up = 0, right = 1, down = 2, left = 3 };

pub const LineSegment = struct {
    start: PointF,
    end: PointF,
    pub fn intersects(self: LineSegment, other: LineSegment) ?PointF {
        const p0_x = self.start.x;
        const p0_y = self.start.y;
        const p1_x = self.end.x;
        const p1_y = self.end.y;
        const p2_x = other.start.x;
        const p2_y = other.start.y;
        const p3_x = other.end.x;
        const p3_y = other.end.y;

        const s1_x = p1_x - p0_x;
        const s1_y = p1_y - p0_y;
        const s2_x = p3_x - p2_x;
        const s2_y = p3_y - p2_y;

        const s_n = (-s1_x * (p0_x - p2_x) + s1_x * (p0_y - p2_y));
        if (s_n == 0)
            return null;
        const s_d = (-s2_x * s1_y + s1_x * s2_y);
        if (s_d == 0)
            return null;
        const s = s_n / s_d;
        const t_n = (s2_x * (p0_x - p2_y) - s2_y * (p0_x - p2_x));
        const t_d = (-s2_x * s1_y + s1_x * s2_y);
        if (t_d == 0)
            return null;
        const t = t_n / t_d;
        if (s >= 0 and s <= 1 and t >= 0 and t <= 1) {
            return .{ .x = p0_x + (t * s1_x), .y = p0_y + (t * s1_y) };
        }

        return null;
    }
};

pub const Ray = struct { start: Point, angle: f32 };
