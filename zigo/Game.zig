// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const zigo = @import("main.zig");
const Colour = zigo.Colour;
const Point = zigo.Point;
const Vec2 = zigo.Vec2;

const Board = @import("Board.zig");
const Points = Board.Points;

const Game = @This();

pub fn evenGame(allocator: Allocator) error{OutOfMemory}!Game {
    return try Game.init(allocator, 19, 19, 7);
}

const History = struct {
    const prefix_len = 3;
    const IndexSize = u32;
    // TODO: Consider using std.SegmentedList?
    const List = std.ArrayListUnmanaged([prefix_len]IndexSize);
    const initial_item = [1]IndexSize{0} ** prefix_len;

    list: List,

    fn init(allocator: Allocator, board: Board, player: Colour) error{OutOfMemory}!History {
        var history = History{ .list = try List.initCapacity(allocator, board.getLength() + 1) };
        history.list.appendAssumeCapacity(initial_item);
        history.insert(allocator, board, player.getOpposite()) catch unreachable;
        return history;
    }

    fn deinit(self: *History, allocator: Allocator) void {
        self.list.deinit(allocator);
    }

    fn insert(self: *History, allocator: Allocator, board: Board, player: Colour) error{ BoardRepetition, OutOfMemory }!void {
        var index: IndexSize = 0;

        // Keep iterating while the `index` has previously been reached.
        var i: u16 = 0;
        while (i < board.getLength() - 1) : (i += 1) {
            const int = board.points.get(i);

            if (self.list.items[index][int] == 0) {
                self.list.items[index][int] = @intCast(self.list.items.len);
                index = @intCast(self.list.items.len);

                break;
            }

            index = self.list.items[index][int];
        }

        // If a new state has been reached, record it.
        if (i != board.getLength() - 1) {
            try self.list.appendNTimes(allocator, initial_item, board.getLength() - i - 1);

            for (i + 1..board.getLength() - 1) |j| {
                const int = board.points.get(@intCast(j));
                self.list.items[index][int] = index + 1;
                index += 1;
            }
        }

        // The last point maps to the mask of players that have reached the
        // particular board state.
        const int = board.points.get(board.getLength() - 1);
        const player_mask = @shlExact(@as(u2, 1), @intFromEnum(player));

        if (self.list.items[index][int] & player_mask != 0)
            return error.BoardRepetition;

        self.list.items[index][int] |= player_mask;
    }
};

const MoveError = error{
    AlreadyOccupied,
    BoardRepetition,
    OutOfMemory,
};

const Winner = enum(u2) {
    undecided = 0b00,
    black = 0b01,
    white = 0b10,
    draw = 0b11,

    inline fn fromColour(colour: Colour) Winner {
        return @enumFromInt(@as(u2, @intFromEnum(colour)) + 1);
    }
};

allocator: Allocator,
player: Colour = .black,
// TODO: Consider signed integer.
komi: u16 = 0,
winner: Winner = .undecided,
board: Board,
// TODO: Remove this by ridding some abstractions.
/// A backup of the board to be restored in case of move repetition.
backup: Points,
history: History,

pub fn init(allocator: Allocator, width: u8, height: u8, komi: u16) error{OutOfMemory}!Game {
    const board = try Board.init(allocator, width, height);

    return Game{
        .allocator = allocator,
        .komi = komi,
        .board = board,
        .backup = .{ .bytes = try allocator.alloc(u8, board.points.bytes.len) },
        .history = try History.init(allocator, board, .black),
    };
}

pub fn deinit(self: *Game) void {
    self.board.deinit(self.allocator);
    self.allocator.free(self.backup.bytes);
    self.history.deinit(self.allocator);
}

pub fn play(self: *Game, coord: Vec2) MoveError!void {
    @memcpy(self.backup.bytes, self.board.points.bytes);
    try self.board.placeStone(coord, self.player);
    errdefer @memcpy(self.board.points.bytes, self.backup.bytes);
    try self.insertHistory();
    self.player = self.player.getOpposite();
}

test "play" {
    const allocator = testing.allocator;
    {
        var game = try Game.init(allocator, 1, 1, 0);
        defer game.deinit();

        try game.play(.{ .x = 0, .y = 0 });
        try testing.expectError(error.BoardRepetition, game.play(.{ .x = 0, .y = 0 }));
    }
    {
        var game = try Game.init(allocator, 4, 3, 0);
        defer game.deinit();

        try game.play(.{ .x = 0, .y = 1 });
        try game.play(.{ .x = 3, .y = 1 });
        try game.play(.{ .x = 1, .y = 0 });
        try game.play(.{ .x = 2, .y = 0 });
        try game.play(.{ .x = 1, .y = 2 });
        try game.play(.{ .x = 2, .y = 2 });
        try game.play(.{ .x = 2, .y = 1 });
        try game.play(.{ .x = 1, .y = 1 });
        try testing.expectError(error.BoardRepetition, game.play(.{ .x = 2, .y = 1 }));
    }
}

/// The game ends when passing results in a move repetition.
pub fn pass(self: *Game) void {
    self.insertHistory() catch return {
        var scores = self.board.getScores();
        scores[1] +|= self.getKomi();

        if (scores[0] == scores[1])
            self.winner = .draw
        else if (scores[0] > scores[1])
            self.winner = .black
        else
            self.winner = .white;
    };
    self.player = self.player.getOpposite();
}

test "pass" {
    const allocator = testing.allocator;
    {
        var game = try Game.init(allocator, 1, 1, 0);
        defer game.deinit();

        game.pass();
        game.pass();
        try testing.expectEqual(Winner.draw, game.winner);
    }
}

pub inline fn forfeit(self: *Game, forfeiter: Colour) void {
    self.winner = Winner.fromColour(forfeiter.getOpposite());
}

pub inline fn getKomi(self: Game) u16 {
    return self.komi;
}

fn insertHistory(self: *Game) error{ BoardRepetition, OutOfMemory }!void {
    try self.history.insert(self.allocator, self.board, self.player);
}
