//! General-purpose representation of a package.

allocator: std.mem.Allocator,
name: []const u8,
version: Version,
description: []const u8,
// https://spdx.org/licenses/
// https://spdx.github.io/spdx-spec/v3.0.1/annexes/spdx-license-expressions/
license: []const u8,
// run_dependencies: []const Dependency,

name_version_string: ?[]const u8 = null,

const Package = @This();

// pub const Dependency = struct {
//     name: []const u8,
//     minimum: Version,
//     maximum: Version,
// };

const Version = struct {
    string: []const u8,
    release: u32,
    prerelease: bool,
    epoch: u32,
};

pub fn deinit(self: *Package) void {
    if (self.name_version_string) |f| self.allocator.free(f);
}

pub fn getNameVersionString(self: *Package) ![]const u8 {
    if (self.name_version_string) |f| return f;

    var list = std.ArrayList(u8).init(self.allocator);
    errdefer list.deinit();
    try list.appendSlice(self.name);
    if (self.version.epoch > 0) {
        try std.fmt.formatInt(self.version.epoch, 10, .lower, .{}, list.writer());
        try list.append(':');
    }
    try list.append('-');
    try list.appendSlice(self.version.string);
    try list.append('-');
    try std.fmt.formatInt(self.version.release, 10, .lower, .{}, list.writer());
    self.name_version_string = try list.toOwnedSlice();
    return self.name_version_string.?;
}

fn tokenizeVersion(allocator: std.mem.Allocator, version: []const u8) ![]const []const u8 {
    std.debug.assert(validVersionString(version));
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
            'a'...'z', '_' => {
                state = .letters;
                i += 1;
            },
            '.' => {
                i += 1;
                start = i;
            },
            else => unreachable,
        },
        .number => switch (version[i]) {
            '0'...'9' => {
                i += 1;
            },
            'a'...'z', '_' => {
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
            else => unreachable,
        },
        .letters => switch (version[i]) {
            '0'...'9' => {
                try list.append(version[start..i]);
                state = .number;
                start = i;
            },
            'a'...'z', '_' => {
                i += 1;
            },
            '.' => {
                try list.append(version[start..i]);
                state = .start;
                i += 1;
                start = i;
            },
            else => unreachable,
        },
    };
    switch (state) {
        .start => unreachable,
        else => try list.append(version[start..i]),
    }
    return try list.toOwnedSlice();
}

/// Compare function for as many kinds of version strings as we can handle.
pub fn versionCompare(
    allocator: std.mem.Allocator,
    a_: Version,
    b_: Version,
) !std.math.Order {
    const epochs = std.math.order(a_.epoch, b_.epoch);
    if (epochs != .eq) return epochs;

    const a = try tokenizeVersion(allocator, a_.string);
    defer allocator.free(a);
    const b = try tokenizeVersion(allocator, b_.string);
    defer allocator.free(b);

    const len = @min(a.len, b.len);
    for (a[0..len], b[0..len]) |as, bs| {
        if (util.allAreAlphabetic(as) or util.allAreAlphabetic(bs)) {
            const order = std.mem.order(u8, as, bs);
            if (order != .eq) return order;
        } else {
            // These won't fail due to any alpha characters, and any other failure is on the user.
            const parsed_a = try std.fmt.parseInt(u64, as, 10);
            const parsed_b = try std.fmt.parseInt(u64, bs, 10);
            const order = std.math.order(parsed_a, parsed_b);
            if (order != .eq) return order;
        }
    }

    if (a_.prerelease and !b_.prerelease) return .lt;
    if (!a_.prerelease and b_.prerelease) return .gt;

    return std.math.order(a.len, b.len);
}

test versionCompare {
    try std.testing.expect(
        versionCompare(
            std.testing.allocator,
            .{ .string = "1.2.3", .prerelease = false, .epoch = 0, .release = 0 },
            .{ .string = "1.2.3", .prerelease = false, .epoch = 0, .release = 0 },
        ) catch unreachable == .eq,
    );
    try std.testing.expect(
        versionCompare(
            std.testing.allocator,
            .{ .string = "1.2.4", .prerelease = false, .epoch = 0, .release = 0 },
            .{ .string = "1.2.3", .prerelease = false, .epoch = 0, .release = 0 },
        ) catch unreachable == .gt,
    );
    try std.testing.expect(
        versionCompare(
            std.testing.allocator,
            .{ .string = "1.2.3a", .prerelease = false, .epoch = 0, .release = 0 },
            .{ .string = "1.2.3b", .prerelease = false, .epoch = 0, .release = 0 },
        ) catch unreachable == .lt,
    );
    try std.testing.expect(
        versionCompare(
            std.testing.allocator,
            .{ .string = "apple", .prerelease = false, .epoch = 0, .release = 0 },
            .{ .string = "banana", .prerelease = false, .epoch = 0, .release = 0 },
        ) catch unreachable == .lt,
    );
    try std.testing.expect(
        versionCompare(
            std.testing.allocator,
            .{ .string = "1", .prerelease = false, .epoch = 1, .release = 0 },
            .{ .string = "2", .prerelease = false, .epoch = 0, .release = 0 },
        ) catch unreachable == .gt,
    );
    try std.testing.expect(
        versionCompare(
            std.testing.allocator,
            .{ .string = "1.0.0", .prerelease = false, .epoch = 0, .release = 0 },
            .{ .string = "1.0.0_pre420", .prerelease = true, .epoch = 0, .release = 0 },
        ) catch unreachable == .gt,
    );
}

pub fn validVersionString(version: []const u8) bool {
    // The version string can't be empty.
    if (version.len == 0) return false;

    // Dots are delimiters and the strings between them can't be empty.
    if (version[0] == '.' or version[version.len - 1] == '.') return false;
    if (std.mem.indexOfPos(u8, version, 0, "..")) |_| return false;

    // These characters only.
    for (version) |c| switch (c) {
        'a'...'z', '0'...'9', '.', '_' => {},
        else => return false,
    };

    return true;
}

test validVersionString {
    try std.testing.expect(validVersionString("1.2.3.4.5.6.7.8"));
    try std.testing.expect(validVersionString("a.b.c.d.e.f.g.h"));
    try std.testing.expect(validVersionString("1234.abcd"));
    try std.testing.expect(validVersionString("1"));
    try std.testing.expect(validVersionString("a"));
    try std.testing.expect(validVersionString("1.0.0"));
    try std.testing.expect(!validVersionString("A"));
    try std.testing.expect(!validVersionString("?"));
    try std.testing.expect(!validVersionString("-"));
    try std.testing.expect(!validVersionString(".1.2.3.4"));
    try std.testing.expect(!validVersionString("1.2.3.4."));
    try std.testing.expect(!validVersionString("............."));
}

const std = @import("std");
const util = @import("util.zig");
