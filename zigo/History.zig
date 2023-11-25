// SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>
//
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;

const zigo = @import("main.zig");
const Colour = zigo.Colour;

const Board = @import("Board.zig");

const History = @This();

const prefix_len = 3;
const IndexSize = u32;
// TODO: Consider using std.SegmentedList?
const List = std.ArrayListUnmanaged([prefix_len]IndexSize);
const initial_item = [1]IndexSize{0} ** prefix_len;

list: List,

pub fn init(
    allocator: Allocator,
    board: Board,
    player: Colour,
) error{OutOfMemory}!History {
    var history = History{ .list = try List.initCapacity(allocator, board.getLength() + 1) };
    history.list.appendAssumeCapacity(initial_item);
    history.insert(allocator, board, player.getOpposite()) catch unreachable;
    return history;
}

pub fn deinit(self: *History, allocator: Allocator) void {
    self.list.deinit(allocator);
}

pub fn insert(
    self: *History,
    allocator: Allocator,
    board: Board,
    player: Colour,
) error{ BoardRepetition, OutOfMemory }!void {
    var index: IndexSize = 0;

    // Keep iterating while the `index` has previously been reached.
    var i: u16 = 0;
    while (i < board.getLength() - 1) : (i += 1) {
        const int = @intFromEnum(board.points.get(i));

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
            const int = @intFromEnum(board.points.get(@intCast(j)));
            self.list.items[index][int] = index + 1;
            index += 1;
        }
    }

    // The last point maps to the mask of players that have reached the
    // particular board state.
    const int = @intFromEnum(board.points.get(board.getLength() - 1));
    const player_mask = @shlExact(@as(u2, 1), @intFromEnum(player));

    if (self.list.items[index][int] & player_mask != 0)
        return error.BoardRepetition;

    self.list.items[index][int] |= player_mask;
}
