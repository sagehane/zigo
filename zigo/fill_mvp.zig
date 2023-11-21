const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Point = enum(u2) {
    empty = 0b00,
    black = 0b01,
    white = 0b10,
    // Meaningless in regular play, used for territory counting
    debug = 0b11,

    pub inline fn toMask(self: Point) u4 {
        return @shlExact(1, @intFromEnum(self));
    }
};

const Vec2 = packed struct(u16) { x: u8, y: u8 };

fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        read_index: u16 = 0,
        write_index: u16 = 0,

        pub fn init(allocator: Allocator, capacity: u16) error{OutOfMemory}!Self {
            //const data = try allocator.alloc(T, capacity);
            // Needed to fix behaviour with 1x1 boards?
            const data = try allocator.alloc(T, @max(capacity, 2));
            return .{ .data = data };
        }

        /// Must be the same allocator passed to `init`.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.data);
        }

        inline fn reset(self: *Self) void {
            self.read_index = 0;
            self.write_index = 0;
        }

        inline fn isEmpty(self: Self) bool {
            return self.read_index == self.write_index;
        }

        /// Asserts that the buffer isn't empty.
        inline fn read(self: *Self) T {
            assert(!self.isEmpty());

            const item = self.data[self.read_index];
            self.read_index = @intCast((self.read_index +% 1) % self.data.len);
            return item;
        }

        /// Asserts that the buffer isn't full.
        inline fn write(self: *Self, item: T) void {
            self.data[self.write_index] = item;
            self.write_index = @intCast((self.write_index +% 1) % self.data.len);

            assert(!self.isEmpty());
        }
    };
}

/// Essentially a std.PackedIntSlice optimised for `u2`.
const Points = struct {
    bytes: []u8,

    pub inline fn get(self: Points, index: u16) Point {
        const offset: u3 = @truncate(index << 1);
        return @enumFromInt(@as(u2, @truncate(self.bytes[index >> 2] >> offset)));
    }

    inline fn set(self: *Points, index: u16, point: Point) void {
        const offset: u3 = @truncate(index << 1);
        self.bytes[index >> 2] &= ~@shlExact(@as(u8, 0b11), offset);
        self.bytes[index >> 2] |= @shlExact(@as(u8, @intFromEnum(point)), offset);
    }
};

const Board = struct {
    width: u8,
    height: u8,
    points: Points,
    ring_buffer: RingBuffer,

    pub inline fn bytesRequired(len: u16) u16 {
        return (@bitSizeOf(u2) * len + 7) >> 3;
    }

    inline fn inRange(self: Board, x: u8, y: u8) bool {
        return (self.width > x and self.height > y);
    }

    inline fn coordToIndex(self: Board, x: u8, y: u8) u16 {
        assert(self.inRange(x, y));
        return @as(u16, self.width) * y + x;
    }

    inline fn getPoint(self: Board, x: u8, y: u8) Point {
        assert(self.inRange(x, y));
        return self.points.get(self.coordToIndex(x, y));
    }

    inline fn setPoint(self: *Board, x: u8, y: u8, point: Point) Point {
        assert(self.inRange(x, y));
        return self.points.set(self.coordToIndex(x, y), point);
    }

    inline fn inside(self: Board, x: u8, y: u8, from: Point) bool {
        return (x < self.width) and self.getPoint(x, y) == from;
    }

    fn fill(
        self: *Board,
        x: u8,
        y: u8,
        from: Point,
        to: Point,
    ) void {
        if (!self.inside(x, y, from)) return;

        self.ring_buffer.reset();
        self.ring_buffer.write(.{ x, x, y, 1 });
        self.ring_buffer.write(.{ x, x, y - 1, -1 });

        var _x: u8 = undefined;
        var _y: u8 = undefined;
        var x1: u8 = undefined;
        var x2: u8 = undefined;
        var dy: u8 = undefined;
        var item: [4]u8 = undefined;
        while (!self.ring_buffer.isEmpty()) {
            item = self.ring_buffer.read();

            x1 = item[0];
            x2 = item[1];
            _y = item[2];
            dy = item[3];

            _x = x1;

            if (self.inside(_x, _y, from)) {
                while (self.inside(_x -% 1, _y, from)) {
                    self.setPoint(_x - 1, _y, to);
                    _x -%= 1;
                }
                if (_x < x1)
                    self.ring_buffer.write(.{ _x, x1 - 1, y - dy, -dy });
            }

            while (x1 <= x2) {
                while (self.inside(x1, _y, from)) {
                    self.setPoint(x1, _y, to);
                    x1 += 1;
                }
                if (x1 > _x)
                    self.ring_buffer.write(.{ _x, x1 - 1, _y + dy, dy });
                if (x1 - 1 > x2)
                    self.ring_buffer.write(.{ x2 + 1, x1 - 1, _y - dy, -dy });
                x1 += 1;
                while (x1 < x2 and !self.inside(x1, _y))
                    x1 += 1;
                _x = x1;
            }
        }
    }
};
