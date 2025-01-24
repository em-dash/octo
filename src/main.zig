pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("this package manager hates mushrooms\n", .{});
    try bw.flush();
}

const std = @import("std");

// const Package = @import("Package.zig");
// const SourcePackage = @import("SourcePackage.zig");

test {
    std.testing.refAllDeclsRecursive(@import("Package.zig"));
    std.testing.refAllDeclsRecursive(@import("SourcePackage.zig"));
}
