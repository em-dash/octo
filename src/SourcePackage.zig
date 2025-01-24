package: Package,
source: std.Uri,
build_step: []const u8,

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

// pub fn init()

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
    const uri_text = "https://github.com/em-dash/hello-test/archive/refs/tags/v1.0.0.tar.gz";
    var fetch_tmpdir = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer fetch_tmpdir.cleanup();
    var build_tmpdir = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer build_tmpdir.cleanup();
    const fetch_dir = fetch_tmpdir.dir;
    const build_dir = build_tmpdir.dir;

    var source_package = SourcePackage{
        .package = .{
            .allocator = std.testing.allocator,
            .name = "hello-test",
            .version = .{ .string = "1.0.0", .prerelease = false, .epoch = 0, .release = 0 },
            .description = "A hello world project for fun and profit.",
            .license = "MIT",
            .run_dependencies = &[_]Package.Dependency{},
        },
        .source = try std.Uri.parse(uri_text),
        .build_step = "zig build install -Doptimize=ReleaseFast -Dcpu=baseline",
        .fetch_dir = fetch_dir,
        .build_dir = build_dir,
    };
    defer source_package.deinit();

    try source_package.fetch();
    try source_package.unpack();
    try source_package.build();
}

const std = @import("std");
const Package = @import("Package.zig");
const util = @import("util.zig");
