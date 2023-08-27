// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;

const zigo = @import("main.zig");
const Colour = zigo.Colour;
const Point = zigo.Point;
const Vec2 = zigo.Vec2;

const BoardError = error{AlreadyOccupied};

// TODO: Make the dimensions configurable at runtime.
pub fn Board(comptime dimensions: Vec2) type {
    const width: u16 = dimensions.x;
    const height: u16 = dimensions.y;
    const length = width * height;

    if (width == 0 or height == 0)
        @compileError("The width or height cannot be 0.");

    return struct {
        const Self = @This();

        // TODO: Consider using something like ArrayList?
        points: [length]Point = [1]Point{.empty} ** length,

        // TODO
        // Pack into u8 using `length >> 2 + @intFromBool(length & 0b11 > 0)`
        //points: [packed_length]u8 = [1]u8{0} ** packed_length,

        pub fn placeStone(self: *Self, coord: Vec2, colour: Colour) BoardError!void {
            if (self.getPoint(coord) != .empty)
                return error.AlreadyOccupied;

            const point = colour.toPoint();
            self.setPoint(coord, point);

            var board_copy = self.*;
            var buffer: [4]Vec2 = undefined;
            const adjacents = getAdjacents(coord, &buffer);

            var capture_flag: u4 = 0;
            for (adjacents, 0..) |adj_coord, i| {
                if (self.getPoint(adj_coord) == point.getOpposite() and
                    board_copy.floodFillCheck(adj_coord))
                    capture_flag |= @as(u4, 1) << @intCast(i);
            }

            if (capture_flag != 0) {
                for (adjacents, 0..) |adj_coord, i|
                    if (capture_flag & (@as(u4, 1) << @intCast(i)) != 0)
                        self.captureGroup(adj_coord);
            } else {
                board_copy = self.*;
                if (board_copy.floodFillCheck(coord))
                    self.captureGroup(coord);
            }
        }

        /// Returns a board representing the territory of each player.
        pub fn getTerritory(self: Self) Self {
            var territory = self;

            for (0..width) |x| for (0..height) |y| {
                const coord = Vec2{ .x = @intCast(x), .y = @intCast(y) };
                if (territory.getPoint(coord) != .empty) continue;

                const owner = territory.getOwner(coord);
                if (owner.isColour())
                    territory.fillTerritory(coord, owner);
            };

            return territory;
        }

        /// The first index contains black's score and the second contains white's.
        pub fn getScores(self: Self) [2]u16 {
            const territory = self.getTerritory();
            var scores = [2]u16{ 0, 0 };

            for (0..width) |x| for (0..height) |y| {
                const coord = Vec2{ .x = @intCast(x), .y = @intCast(y) };
                const point = territory.getPoint(coord);

                if (!point.isColour()) continue;

                scores[@intFromEnum(point.toColour())] += 1;
            };

            return scores;
        }

        /// Must be called on a coordinate containing an empty point.
        /// Converts `.empty` into `.debug` and returns owner of the territory.
        /// Returns `.empty` if neither players are adjacent to the territory.
        /// Returns `.debug` if both players are adjacent to the territory.
        fn getOwner(self: *Self, coord: Vec2) Point {
            var owner = self.getPoint(coord);
            if (owner.isColour()) return owner;

            self.setPoint(coord, .debug);

            var buffer: [4]Vec2 = undefined;
            for (getAdjacents(coord, &buffer)) |adj_coord|
                if (self.getPoint(adj_coord) != .debug) {
                    const adj_owner = self.getOwner(adj_coord);
                    owner = @enumFromInt(@intFromEnum(owner) | @intFromEnum(adj_owner));
                };

            return owner;
        }

        fn fillTerritory(self: *Self, coord: Vec2, owner: Point) void {
            self.setPoint(coord, owner);

            var buffer: [4]Vec2 = undefined;
            for (getAdjacents(coord, &buffer)) |adj_coord| {
                if (!self.getPoint(adj_coord).isColour())
                    self.fillTerritory(adj_coord, owner);
            }
        }

        // TODO: Look into scanline
        /// Returns `true` if the stones are dead.
        fn floodFillCheck(self: *Self, coord: Vec2) bool {
            const point = self.getPoint(coord);
            if (point == .empty) return false;

            self.setPoint(coord, point.getOpposite());

            var buffer: [4]Vec2 = undefined;
            for (getAdjacents(coord, &buffer)) |adj_coord|
                if (self.getPoint(adj_coord) != point.getOpposite() and
                    !self.floodFillCheck(adj_coord))
                    return false;

            return true;
        }

        test "floodFillCheck" {
            {
                var a = Board(.{ .x = 1, .y = 1 }){};
                a.setPoint(.{ .x = 0, .y = 0 }, .black);
                try testing.expect(a.floodFillCheck(.{ .x = 0, .y = 0 }));
            }
            {
                var a = Board(.{ .x = 2, .y = 1 }){};
                a.setPoint(.{ .x = 0, .y = 0 }, .black);
                try testing.expect(!a.floodFillCheck(.{ .x = 0, .y = 0 }));
            }
            {
                var a = Board(.{ .x = 2, .y = 1 }){};
                a.setPoint(.{ .x = 0, .y = 0 }, .black);
                a.setPoint(.{ .x = 1, .y = 0 }, .white);
                try testing.expect(a.floodFillCheck(.{ .x = 0, .y = 0 }));
            }
        }

        fn captureGroup(self: *Self, coord: Vec2) void {
            const point = self.getPoint(coord);
            self.setPoint(coord, .empty);

            var buffer: [4]Vec2 = undefined;
            for (getAdjacents(coord, &buffer)) |adj_coord|
                if (self.getPoint(adj_coord) == point)
                    self.captureGroup(adj_coord);
        }

        test "captureGroup" {
            {
                var a = Board(.{ .x = 1, .y = 1 }){};
                var b = a;

                b.setPoint(.{ .x = 0, .y = 0 }, .black);
                b.captureGroup(.{ .x = 0, .y = 0 });

                try expectEqual(a, b);
            }
            {
                var a = Board(.{ .x = 2, .y = 1 }){};
                var b = a;
                a.setPoint(.{ .x = 1, .y = 0 }, .white);

                b.setPoint(.{ .x = 0, .y = 0 }, .black);
                b.setPoint(.{ .x = 1, .y = 0 }, .white);
                b.captureGroup(.{ .x = 0, .y = 0 });

                try expectEqual(a, b);
            }
        }

        pub inline fn getPoint(self: Self, coord: Vec2) Point {
            return self.points[coordToIndex(coord)];
        }

        inline fn setPoint(self: *Self, coord: Vec2, point: Point) void {
            self.points[coordToIndex(coord)] = point;
        }

        // Branchless might be slower?
        fn getAdjacents(coord: Vec2, buffer: *[4]Vec2) []Vec2 {
            var i: u8 = 0;

            buffer[i] = .{ .x = coord.x -% 1, .y = coord.y };
            i += @intFromBool(coord.x != 0);

            buffer[i] = .{ .x = coord.x + 1, .y = coord.y };
            i += @intFromBool(coord.x != width - 1);

            buffer[i] = .{ .x = coord.x, .y = coord.y -% 1 };
            i += @intFromBool(coord.y != 0);

            buffer[i] = .{ .x = coord.x, .y = coord.y + 1 };
            i += @intFromBool(coord.y != height - 1);

            return buffer[0..i];
        }

        test "getAdjacents" {
            const BoardType = Board(.{ .x = 1, .y = 1 });
            var buffer: [4]Vec2 = undefined;
            try expectEqualSlices(Vec2, &.{}, BoardType.getAdjacents(.{ .x = 0, .y = 0 }, &buffer));
        }

        pub inline fn inRange(coord: Vec2) bool {
            return (dimensions.x > coord.x and dimensions.y > coord.y);
        }

        inline fn coordToIndex(coord: Vec2) u16 {
            assert(inRange(coord));
            return width * coord.y + coord.x;
        }

        // TODO: Consider using some buffer.
        // TODO: Consider supporting bigger widths.
        pub fn printAscii(self: Self, writer: anytype) !void {
            if (width > 26) @compileError("Only width up to 26 is supported.");

            const pad = comptime std.math.log10(height);
            const pad_str = "  " ++ " " ** pad;

            try writer.writeAll(pad_str);
            for (0..width) |i| {
                try writer.print(" {c}", .{'A' + @as(u8, @intCast(i))});
            }
            try writer.writeAll("\n");

            for (0..height) |i| {
                const row = height - @as(u8, @intCast(i));
                const mark_str = " {d:>" ++ .{'1' + pad} ++ "}";

                try writer.print(mark_str, .{row});
                for (self.points[width * (row - 1) .. width * (row - 1) + width]) |point| {
                    try writer.print(" {c}", .{point.toChar()});
                }
                try writer.print(mark_str ++ "\n", .{row});
            }

            try writer.writeAll(pad_str);
            for (0..width) |i| {
                try writer.print(" {c}", .{'A' + @as(u8, @intCast(i))});
            }
            try writer.writeAll("\n");
        }
    };
}

// TODO: Make a `expectEqualBoards` function that prints a board given a test failure.

test "self-capture" {
    {
        const a = Board(.{ .x = 1, .y = 1 }){};
        var b = a;
        try b.placeStone(.{ .x = 0, .y = 0 }, .black);
        try expectEqual(a, b);
    }

    {
        const a = Board(.{ .x = 2, .y = 1 }){};
        var b = a;
        b.setPoint(.{ .x = 0, .y = 0 }, .black);
        try b.placeStone(.{ .x = 1, .y = 0 }, .black);
        try expectEqual(a, b);
    }
}

test "capture" {
    var a = Board(.{ .x = 2, .y = 1 }){};
    var b = a;
    a.setPoint(.{ .x = 1, .y = 0 }, .white);
    b.setPoint(.{ .x = 0, .y = 0 }, .black);
    try b.placeStone(.{ .x = 1, .y = 0 }, .white);
    try expectEqual(a, b);
}
