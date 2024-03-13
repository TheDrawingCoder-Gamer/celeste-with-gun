const types = @This();

const std = @import("std");
const tic = @import("common").tic;
const math = @import("common").math;

pub usingnamespace math;

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
    pub fn top_left(self: AABB) math.Vec2 {
        return .{ .x = self.x, .y = self.y };
    }
    pub fn aabb_cast(source: AABB, target: AABB, direction: math.Vec2, max_distance: f32) ?Ray.Hit {
        const ray = Ray.create(.{ .x = source.x + source.w / 2.0, .y = source.y + source.h / 2.0 }, direction);
        var good_target = target;
        good_target.x -= source.w / 2;
        good_target.y -= source.h / 2;
        good_target.w += source.w;
        good_target.h += source.h;
        return ray.raycast(good_target, max_distance);
    }

    pub fn offset(self: AABB, by: math.Vec2) AABB {
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
    start: math.PointF,
    end: math.PointF,
    pub fn intersects(p_line: LineSegment, q_line: LineSegment) ?math.PointF {
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

pub const AngledLine = struct {
    line: LineSegment,
    angle: f32,
    pub fn debug_draw(self: AngledLine, cam: types.PointF, color: u4, angle_color: u4) void {
        self.line.debug_draw(cam, color);
        const diff = self.line.end.minus(self.line.start);
        const midpoint = self.line.start.add(diff.times(0.5));
        const point = math.PointF.from_radians(self.angle);
        _ = tic.vbank(1);
        const sx = midpoint.x - cam.x;
        const sy = midpoint.y - cam.y;
        tic.line(sx, sy, sx + point.x * 4, sy + point.y * 4, angle_color);
        _ = tic.vbank(0);
    }
};

pub const Ray = struct {
    pub const Hit = struct {
        point: math.Vec2,
        normal: math.Vec2,
        distance: f32,
    };
    start: math.Vec2,
    direction: math.Vec2,
    pub fn create(origin: math.Vec2, direction: math.Vec2) Ray {
        return .{ .start = origin, .direction = direction.normalized() };
    }
    pub fn from_to(from: math.Vec2, to: math.Vec2) Ray {
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
