pub const Point = struct { x: i32 = 0, y: i32 = 0 };

pub fn approach(x: anytype, target: anytype, max_delta: anytype) @TypeOf(x, target, max_delta) {
    return if (x < target) @min(x + max_delta, target) else @max(x - max_delta, target);
}

pub fn lerp(min: f32, max: f32, t: f32) f32 {
    return (1 - t) * min + t * max;
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
};

pub const Direction = enum(u2) { up = 0, right = 1, down = 2, left = 3 };
