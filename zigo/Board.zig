// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;

const zigo = @import("main.zig");
const Colour = zigo.Colour;
const Point = zigo.Point;
const Vec2 = zigo.Vec2;

const Board = @This();

const BoardError = error{AlreadyOccupied};

pub const Points = struct {
    bytes: []u8,

    pub inline fn bytesRequired(len: u16) u16 {
        return (@bitSizeOf(u2) * len + 7) >> 3;
    }

    pub inline fn get(self: Points, index: u16) u2 {
        const offset: u3 = @truncate(index << 1);
        return @truncate(self.bytes[index >> 2] >> offset);
    }

    inline fn set(self: *Points, index: u16, point: u2) void {
        const offset: u3 = @truncate(index << 1);
        self.bytes[index >> 2] &= ~@shlExact(@as(u8, 0b11), offset);
        self.bytes[index >> 2] |= @shlExact(@as(u8, point), offset);
    }
};

width: u8,
height: u8,
points: Points,
/// Used for checking captures and territory counting
copy: Points,

pub fn init(allocator: Allocator, width: u8, height: u8) error{OutOfMemory}!Board {
    assert(width != 0 and height != 0);

    const length: u16 = @as(u16, width) * height;
    const packed_length = Points.bytesRequired(length);

    const bytes = try allocator.alloc(u8, packed_length);
    @memset(bytes, 0);

    return .{
        .width = width,
        .height = height,
        .points = .{ .bytes = bytes },
        .copy = .{ .bytes = try allocator.dupe(u8, bytes) },
    };
}

pub fn deinit(self: Board, allocator: Allocator) void {
    allocator.free(self.points.bytes);
    allocator.free(self.copy.bytes);
}

pub fn placeStone(self: *Board, coord: Vec2, colour: Colour) BoardError!void {
    if (self.getPoint(self.points, coord).isColour())
        return error.AlreadyOccupied;

    const point = colour.toPoint();
    self.setPoint(&self.points, coord, point);

    self.syncCopy();
    var buffer: [4]Vec2 = undefined;
    const adjacents = self.getAdjacents(coord, &buffer);

    var capture_flag: u4 = 0;
    for (adjacents, 0..) |adj_coord, i| {
        if (self.getPoint(self.copy, adj_coord) == point.getOpposite() and
            self.floodFillCheck(adj_coord))
            capture_flag |= @shlExact(@as(u4, 1), @intCast(i));
    }

    if (capture_flag != 0) {
        for (adjacents, 0..) |adj_coord, i|
            if (capture_flag & @shlExact(@as(u4, 1), @intCast(i)) != 0)
                self.captureGroup(adj_coord);
    } else {
        self.syncCopy();
        if (self.floodFillCheck(coord))
            self.captureGroup(coord);
    }
}

// TODO: Make a `expectEqualBoards` function that prints a board given a test failure.

test "placeStone" {
    const allocator = testing.allocator;

    // self-capture
    {
        var a = try Board.init(allocator, 1, 1);
        defer a.deinit(allocator);

        var b = try Board.init(allocator, 1, 1);
        defer b.deinit(allocator);
        try b.placeStone(.{ .x = 0, .y = 0 }, .black);

        try expectEqualSlices(u8, a.points.bytes, b.points.bytes);
    }
    {
        var a = try Board.init(allocator, 2, 1);
        defer a.deinit(allocator);

        var b = try Board.init(allocator, 2, 1);
        defer b.deinit(allocator);
        b.setPoint(&b.points, .{ .x = 0, .y = 0 }, .black);
        try b.placeStone(.{ .x = 1, .y = 0 }, .black);

        try expectEqualSlices(u8, a.points.bytes, b.points.bytes);
    }

    // capture
    {
        var a = try Board.init(allocator, 2, 1);
        defer a.deinit(allocator);
        a.setPoint(&a.points, .{ .x = 1, .y = 0 }, .white);

        var b = try Board.init(allocator, 2, 1);
        defer b.deinit(allocator);
        b.setPoint(&b.points, .{ .x = 0, .y = 0 }, .black);
        try b.placeStone(.{ .x = 1, .y = 0 }, .white);

        try expectEqualSlices(u8, a.points.bytes, b.points.bytes);
    }
}

/// The first index contains black's score and the second contains white's.
pub fn getScores(self: *Board) [2]u16 {
    self.getTerritory();
    var scores = [2]u16{ 0, 0 };

    for (0..self.width) |x| for (0..self.height) |y| {
        const coord = Vec2{ .x = @intCast(x), .y = @intCast(y) };
        const point = self.getPoint(self.copy, coord);

        if (!point.isColour()) continue;
        scores[@intFromEnum(point.toColour())] += 1;
    };

    return scores;
}

test "getScores" {
    const allocator = testing.allocator;
    {
        var board = try Board.init(allocator, 1, 1);
        defer board.deinit(allocator);

        try std.testing.expectEqual([2]u16{ 0, 0 }, board.getScores());
    }
    {
        var board = try Board.init(allocator, 2, 2);
        defer board.deinit(allocator);

        try std.testing.expectEqual([2]u16{ 0, 0 }, board.getScores());
    }
    {
        var board = try Board.init(allocator, 2, 1);
        defer board.deinit(allocator);
        board.setPoint(&board.points, .{ .x = 0, .y = 0 }, .black);

        try std.testing.expectEqual([2]u16{ 2, 0 }, board.getScores());
    }
    {
        var board = try Board.init(allocator, 2, 2);
        defer board.deinit(allocator);
        board.setPoint(&board.points, .{ .x = 0, .y = 0 }, .black);
        board.setPoint(&board.points, .{ .x = 1, .y = 1 }, .white);

        try std.testing.expectEqual([2]u16{ 1, 1 }, board.getScores());
    }
}

/// Modifies `copy` to a value representing the territory of each player.
fn getTerritory(self: *Board) void {
    self.syncCopy();

    for (0..self.width) |x| for (0..self.height) |y| {
        const coord = Vec2{ .x = @intCast(x), .y = @intCast(y) };
        if (self.getPoint(self.copy, coord) != .empty) continue;

        const owner = self.getOwner(coord);
        if (owner.isColour())
            self.fillTerritory(coord, owner.toColour());
    };
}

/// Must be called on a coordinate containing an empty point.
/// Converts `.empty` into `.debug` and returns owner of the territory.
/// Returns `.empty` if neither players are adjacent to the territory.
/// Returns `.debug` if both players are adjacent to the territory.
fn getOwner(
    self: *Board,
    coord: Vec2,
) Point {
    var owner = self.getPoint(self.copy, coord);
    if (owner.isColour()) return owner;

    self.setPoint(&self.copy, coord, .debug);

    var buffer: [4]Vec2 = undefined;
    for (self.getAdjacents(coord, &buffer)) |adj_coord|
        if (self.getPoint(self.copy, adj_coord) != .debug) {
            const adj_owner = self.getOwner(adj_coord);
            owner = @enumFromInt(@intFromEnum(owner) | @intFromEnum(adj_owner));
        };

    return owner;
}

fn fillTerritory(self: *Board, coord: Vec2, colour: Colour) void {
    self.setPoint(&self.copy, coord, colour.toPoint());

    var buffer: [4]Vec2 = undefined;
    for (self.getAdjacents(coord, &buffer)) |adj_coord| {
        if (self.getPoint(self.copy, adj_coord) == .debug)
            self.fillTerritory(adj_coord, colour);
    }
}

// TODO: Look into scanline
/// Returns `true` if the stones are dead.
/// `syncCopy` must be called before calling this function.
fn floodFillCheck(self: *Board, coord: Vec2) bool {
    const point = self.getPoint(self.copy, coord);
    if (point == .empty) return false;

    self.setPoint(&self.copy, coord, point.getOpposite());

    var buffer: [4]Vec2 = undefined;
    for (self.getAdjacents(coord, &buffer)) |adj_coord|
        if (self.getPoint(self.copy, adj_coord) != point.getOpposite() and
            !self.floodFillCheck(adj_coord))
            return false;

    return true;
}

test "floodFillCheck" {
    const allocator = testing.allocator;
    {
        var a = try Board.init(allocator, 1, 1);
        defer a.deinit(allocator);
        a.setPoint(&a.points, .{ .x = 0, .y = 0 }, .black);
        a.syncCopy();
        try testing.expect(a.floodFillCheck(.{ .x = 0, .y = 0 }));
    }
    {
        var a = try Board.init(allocator, 2, 1);
        defer a.deinit(allocator);
        a.setPoint(&a.points, .{ .x = 0, .y = 0 }, .black);
        a.syncCopy();
        try testing.expect(!a.floodFillCheck(.{ .x = 0, .y = 0 }));
    }
    {
        var a = try Board.init(allocator, 2, 1);
        defer a.deinit(allocator);
        a.setPoint(&a.points, .{ .x = 0, .y = 0 }, .black);
        a.setPoint(&a.points, .{ .x = 1, .y = 0 }, .white);
        a.syncCopy();
        try testing.expect(a.floodFillCheck(.{ .x = 0, .y = 0 }));
    }
}

fn captureGroup(self: *Board, coord: Vec2) void {
    const point = self.getPoint(self.points, coord);
    self.setPoint(&self.points, coord, .empty);

    var buffer: [4]Vec2 = undefined;
    for (self.getAdjacents(coord, &buffer)) |adj_coord|
        if (self.getPoint(self.points, adj_coord) == point)
            self.captureGroup(adj_coord);
}

test "captureGroup" {
    const allocator = testing.allocator;
    {
        var a = try Board.init(allocator, 1, 1);
        defer a.deinit(allocator);

        var b = try Board.init(allocator, 1, 1);
        defer b.deinit(allocator);
        b.setPoint(&b.points, .{ .x = 0, .y = 0 }, .black);
        b.captureGroup(.{ .x = 0, .y = 0 });

        try expectEqualSlices(u8, a.points.bytes, b.points.bytes);
    }
    {
        var a = try Board.init(allocator, 2, 1);
        defer a.deinit(allocator);
        a.setPoint(&a.points, .{ .x = 1, .y = 0 }, .white);

        var b = try Board.init(allocator, 2, 1);
        defer b.deinit(allocator);
        b.setPoint(&b.points, .{ .x = 0, .y = 0 }, .black);
        b.setPoint(&b.points, .{ .x = 1, .y = 0 }, .white);
        b.captureGroup(.{ .x = 0, .y = 0 });

        try expectEqualSlices(u8, a.points.bytes, b.points.bytes);
    }
}

pub inline fn getPoint(self: Board, points: Points, coord: Vec2) Point {
    const index = self.coordToIndex(coord);
    return @enumFromInt(points.get(index));
}

inline fn setPoint(self: Board, points: *Points, coord: Vec2, point: Point) void {
    const index = self.coordToIndex(coord);
    points.set(index, @intFromEnum(point));
}

// Branchless might be slower?
fn getAdjacents(self: Board, coord: Vec2, buffer: *[4]Vec2) []Vec2 {
    var i: u8 = 0;

    buffer[i] = .{ .x = coord.x -% 1, .y = coord.y };
    i += @intFromBool(coord.x != 0);

    buffer[i] = .{ .x = coord.x + 1, .y = coord.y };
    i += @intFromBool(coord.x != self.width - 1);

    buffer[i] = .{ .x = coord.x, .y = coord.y -% 1 };
    i += @intFromBool(coord.y != 0);

    buffer[i] = .{ .x = coord.x, .y = coord.y + 1 };
    i += @intFromBool(coord.y != self.height - 1);

    return buffer[0..i];
}

inline fn syncCopy(self: *Board) void {
    @memcpy(self.copy.bytes, self.points.bytes);
}

test "getAdjacents" {
    const allocator = testing.allocator;
    const board = try Board.init(allocator, 1, 1);
    defer board.deinit(allocator);
    var buffer: [4]Vec2 = undefined;
    try expectEqualSlices(Vec2, &.{}, board.getAdjacents(.{ .x = 0, .y = 0 }, &buffer));
}

pub inline fn inRange(self: Board, coord: Vec2) bool {
    return (self.width > coord.x and self.height > coord.y);
}

inline fn coordToIndex(self: Board, coord: Vec2) u16 {
    assert(self.inRange(coord));
    return @as(u16, self.width) * coord.y + coord.x;
}

// TODO: Consider using some buffer.
// TODO: Consider supporting bigger widths.
pub fn printAscii(self: Board, points: Points, writer: anytype) !void {
    assert(self.width <= 26);

    const pad = std.math.log10(self.height);
    const pad_str = (" " ** 4)[0 .. pad + 2];

    try writer.writeAll(pad_str);
    for (0..self.width) |i| {
        try writer.print(" {c}", .{'A' + @as(u8, @intCast(i))});
    }
    try writer.writeAll("\n");

    for (0..self.height) |i| {
        const y = self.height - @as(u8, @intCast(i)) - 1;
        const len = pad - std.math.log10(y + 1);

        try writer.print(" {s}{d}", .{ (" " ** 2)[0..len], y + 1 });
        for (0..self.width) |x| {
            const point = self.getPoint(points, .{ .x = @intCast(x), .y = y });
            try writer.print(" {c}", .{point.toChar()});
        }
        try writer.print(" {s}{d}\n", .{ (" " ** 2)[0..len], y + 1 });
    }

    try writer.writeAll(pad_str);
    for (0..self.width) |i| {
        try writer.print(" {c}", .{'A' + @as(u8, @intCast(i))});
    }
    try writer.writeAll("\n");
}
