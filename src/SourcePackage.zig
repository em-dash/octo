package: Package,
source: std.Uri,
build_script: []const u8,

fetch_dir: std.fs.Dir,
build_dir: std.fs.Dir,

steps_complete: struct {
    fetch: bool = false,
    unpack: bool = false,
    build: bool = false,
} = .{},

/// Filename for the archive containing the source code.  This field should not be accessed
/// directly; use `getArchiveFilename`.
archive_filename: ?[]const u8 = null,

const SourcePackage = @This();

pub const ZonFile = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    license: []const u8,
    source_url: []const u8,
    build_script: []const u8,
};

pub fn init(
    allocator: std.mem.Allocator,
    zon: ZonFile,
    fetch_dir: std.fs.Dir,
    build_dir: std.fs.Dir,
) !SourcePackage {
    return .{
        .package = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, zon.name),
            .version = .{
                .string = try allocator.dupe(u8, zon.version),
                .prerelease = false,
                .epoch = 0,
                .release = 0,
            },
            .description = try allocator.dupe(u8, zon.description),
            .license = try allocator.dupe(u8, zon.license),
        },
        .source = try std.Uri.parse(zon.source_url),
        .build_step = try allocator.dupe(u8, zon.build),
        .fetch_dir = fetch_dir,
        .build_dir = build_dir,
    };
}

pub fn fetch(self: *SourcePackage) !void {
    const data = try util.fetchUri(self.package.allocator, self.source);
    defer self.package.allocator.free(data);

    const file = try self.fetch_dir.createFile(try self.getArchiveFilename(), .{});
    defer file.close();
    try file.writeAll(data);

    self.steps_complete.fetch = true;
}

pub fn unpack(self: *SourcePackage) !void {
    const archive = try self.fetch_dir.openFile(try self.getArchiveFilename(), .{});
    defer archive.close();
}

pub fn build(self: *SourcePackage) !void {
    _ = self; // autofix
}

pub fn deinit(self: *SourcePackage) void {
    if (self.archive_filename) |f| self.package.allocator.free(f);
    self.package.deinit();
}

fn getArchiveFilename(self: *SourcePackage) ![]const u8 {
    if (self.archive_filename) |f| return f;

    var list: std.ArrayListUnmanaged(u8) = .{};
    errdefer list.deinit(self.package.allocator);

    try list.appendSlice(self.package.allocator, try self.package.getNameVersionString());
    const archive_type = if (util.ArchiveType.fromPath(self.source.path.percent_encoded)) |t|
        t
    else
        return error.UnknownArchiveType;
    try list.appendSlice(self.package.allocator, @tagName(archive_type));

    self.archive_filename = try list.toOwnedSlice(self.package.allocator);
    return self.archive_filename.?;
}

test SourcePackage {
    const hello_test = @import("test_packages.zig").hello_test_source;
    _ = hello_test;
}

const std = @import("std");
const Package = @import("Package.zig");
const util = @import("util.zig");
