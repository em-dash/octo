//! General-purpose representation of a package.

allocator: std.mem.Allocator,
name: []const u8,
version: []const u8,
release: u32,
description: []const u8,
/// https://spdx.org/licenses/
/// https://spdx.github.io/spdx-spec/v3.0.1/annexes/spdx-license-expressions/
license: []const u8,
dependencies: []const Dependency,
// default_options: []const Option,

const Package = @This();

const Dependency = struct {
    name: []const u8,
    minimum: struct { version: []const u8, release: u32 },
    maximum: struct { version: []const u8, release: u32 },
    // required_options: []const Option,
};

// const Option = struct {
//     name: []const u8,
//     value: OptionValue,

//     const OptionValue = union(enum) {
//         bool: bool,
//         int: i32,
//         string: []const u8,
//     };
// };

/// Caller owns returned slice.
fn getNameVersionString(self: Package, allocator: std.mem.Allocator) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try list.appendSlice(self.name);
    try list.append('-');
    try list.appendSlice(self.version);
    try list.append('-');
    try std.fmt.formatInt(self.release, 10, .lower, .{}, list.writer());
    return try list.toOwnedSlice();
}

fn tokenizeVersion(allocator: std.mem.Allocator, version: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer list.deinit();
    var state: enum { start, number, letters } = .start;
    var start: usize = 0;
    var i: usize = 0;
    while (i < version.len) switch (state) {
        .start => switch (version[i]) {
            '0'...'9' => {
                state = .number;
                i += 1;
            },
            'a'...'z' => {
                state = .letters;
                i += 1;
            },
            '.' => {
                i += 1;
                start = i;
            },
        },
        .number => switch (version[i]) {
            '0'...'9' => {
                i += 1;
            },
            'a'...'z' => {
                try list.append(version[start..i]);
                state = .letters;
                start = i;
            },
            '.' => {
                try list.append(version[start..i]);
                state = .start;
                i += 1;
                start = i;
            },
        },
        .letters => switch (version[i]) {
            '0'...'9' => {
                try list.append(version[start..i]);
                state = .numbers;
                start = i;
            },
            'a'...'z' => {
                i += 1;
            },
            '.' => {
                try list.append(version[start..i]);
                state = .start;
                i += 1;
                start = i;
            },
        },
    };
    return try list.toOwnedSlice();
}

pub fn versionCompare(
    allocator: std.mem.Allocator,
    a_: []const u8,
    b_: []const u8,
) !std.math.Order {
    const a = tokenizeVersion(allocator, a_);
    defer allocator.free(a);
    const b = tokenizeVersion(allocator, b_);
    defer allocator.free(b);

    const len = @min(a.len, b.len);
    for (a[0..len], b[0..len]) |as, bs| {
        const parse_a = std.fmt.parseInt(u32, as, 10);
        const parse_b = std.fmt.parseInt(u32, bs, 10);
        if (parse_a == error.Overflow or parse_b == error.Overflow) return error.Overflow;

        if (parse_a == error.InvalidCharacter or parse_b == error.InvalidCharacter) {
            const order = std.mem.order(u8, as, bs);
            if (order != .eq) return order;
        } else {
            const order = std.math.order(parse_a, parse_b);
            if (order != .eq) return order;
        }
    }

    return std.math.order(a.len, b.len);
}

pub fn validVersion(version: []const u8) bool {
    for (version) |c| switch (c) {
        'a'...'z', '1'...'0', '.' => {},
        else => return false,
    };
    return true;
}

pub fn validName(name: []const u8) bool {
    for (name) |c| switch (c) {
        'a'...'z', '1'...'0', '-' => {},
        else => return false,
    };
    return true;
}

const std = @import("std");
const util = @import("util.zig");
