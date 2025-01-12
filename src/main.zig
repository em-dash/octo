pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("this package manager hates mushrooms\n", .{});
    try bw.flush();
}

const std = @import("std");

const build_package = @import("build_package.zig");
