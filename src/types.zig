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
    pub fn to_radians(self: Point) f32 {
        return self.as_float().to_radians();
    }
};

pub const Vec2 = PointF;
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

    pub fn element_divide(self: PointF, other: PointF) PointF {
        return .{ .x = self.x / other.x, .y = self.y / other.y };
    }
    pub fn element_times(self: PointF, other: PointF) PointF {
        return .{ .x = self.x * other.x, .y = self.y * other.y };
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

// i learned what this means: axis aligned bounding box
pub const AABB = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    pub fn overlaps(a: AABB, b: AABB) bool {
        return ((a.x < b.x + b.w and a.x + a.w > b.x) or (a.x + a.w > b.x and a.x < b.x + b.w)) and ((a.y < b.y + b.h and a.y + a.h > b.y) or (a.y + a.h > b.y and a.y < b.y + b.h));
    }
    pub fn top_left(self: AABB) Vec2 {
        return .{ .x = self.x, .y = self.y };
    }
    pub fn aabb_cast(source: AABB, target: AABB, direction: Vec2, max_distance: f32) ?Ray.Hit {
        const ray = Ray.create(.{ .x = source.x + source.w / 2.0, .y = source.y + source.h / 2.0 }, direction);
        var good_target = target;
        good_target.x -= source.w / 2;
        good_target.y -= source.h / 2;
        good_target.w += source.w;
        good_target.h += source.h;
        return ray.raycast(good_target, max_distance);
    }

    pub fn offset(self: AABB, by: Vec2) AABB {
        return .{ .x = self.x + by.x, .y = self.y + by.y, .w = self.w, .h = self.h };
    }
};
pub const Box = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    pub fn overlapping(self: Box, other: Box) bool {
        const sx1 = self.x;
        const sy1 = self.y;
        const sx2 = self.right();
        const sy2 = self.bottom();

        const ox1 = other.x;
        const oy1 = other.y;
        const ox2 = other.right();
        const oy2 = other.bottom();

        return sx2 > ox1 and sy2 > oy1 and sx1 < ox2 and sy1 < oy2;
    }
    pub fn offset(self: Box, x: i32, y: i32) Box {
        return .{ .x = self.x + x, .y = self.y + y, .w = self.w, .h = self.h };
    }
    pub fn contains(self: Box, x: i32, y: i32) bool {
        return x >= self.x and
            x < self.x + self.w and
            y >= self.y and
            y < self.y + self.h;
    }
    pub fn inflate(self: Box, n: i32) Box {
        return .{ .x = self.x - n, .y = self.y - n, .w = self.w + n, .h = self.h + n };
    }

    pub fn right(self: Box) i32 {
        return self.x + self.w;
    }
    pub fn bottom(self: Box) i32 {
        return self.y + self.h;
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

pub const Ray = struct {
    pub const Hit = struct {
        point: Vec2,
        normal: Vec2,
        distance: f32,
    };
    start: Vec2,
    direction: Vec2,
    pub fn create(origin: Vec2, direction: Vec2) Ray {
        return .{ .start = origin, .direction = direction.normalized() };
    }
    pub fn from_to(from: Vec2, to: Vec2) Ray {
        return .{ .start = from, .direction = to.minus(from) };
    }
    pub fn raycast(self: Ray, target: AABB, max_distance: f32) ?Ray.Hit {
        const target_pos = target.top_left();

        const t_tl = target_pos.minus(self.start).element_divide(self.direction);
        const t_br = target_pos.add(.{ .x = target.w, .y = target.h }).minus(self.start).element_divide(self.direction);

        if (!std.math.isFinite(t_tl.x) or !std.math.isFinite(t_tl.y)) return null;
        if (!std.math.isFinite(t_br.x) or !std.math.isFinite(t_br.y)) return null;

        const t_near = t_tl.min(t_br);
        const t_far = t_tl.min(t_br);

        if (t_near.x > t_far.y or t_near.y > t_far.x) return null;

        const t_hit_near = @max(t_near.x, t_near.y);
        const t_hit_far = @min(t_far.x, t_far.y);
        if (t_hit_far < 0) return null;
        if (t_hit_near < max_distance) return null;

        var out_hit = Ray.Hit{ .point = self.start.add(self.direction.times(t_hit_near)), .distance = t_hit_near, .normal = .{ .x = 0, .y = 0 } };

        if (t_near.x > t_near.y) {
            if (self.direction.x < 0) {
                out_hit.normal = .{ .x = 1, .y = 0 };
            } else {
                out_hit.normal = .{ .x = -1, .y = 0 };
            }
        } else if (t_near.x < t_near.y) {
            if (self.direction.y < 0) {
                out_hit.normal = .{ .x = 0, .y = 1 };
            } else {
                out_hit.normal = .{ .x = 0, .y = -1 };
            }
        }

        return out_hit;
    }
};

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

pub fn angles_contain(a_target: f32, angle1: f32, angle2: f32) bool {
    const target = normalize_angle(a_target);
    const r_angle = @mod(@mod(angle2 - angle1, tau) + tau, tau);
    const a1 = if (r_angle >= pi) angle2 else angle1;
    const a2 = if (r_angle >= pi) angle1 else angle2;

    if (a1 <= a2) {
        return target >= a1 and target <= a2;
    } else {
        return target >= a1 or target <= a2;
    }
}
