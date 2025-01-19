const Downloader = struct {
    const header_buffer_size: usize = 1 << 14;

    client: std.http.Client,
    /// Managed by caller.
    url: []const u8,
    storage: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator, url: []const u8) Downloader {
        return .{
            .client = std.http.Client{ .allocator = allocator },
            .url = url,
            .storage = std.ArrayList(u8).init(allocator),
        };
    }

    fn deinit(self: *Downloader) void {
        self.client.deinit();
        self.storage.deinit();
    }

    fn download(self: *Downloader) !std.http.Status {
        const result = try self.client.fetch(.{
            .location = .{ .url = self.url },
            .redirect_behavior = @enumFromInt(5),
            .response_storage = .{ .dynamic = &self.storage },
        });

        return result.status;
    }
};

const BuildOptions = struct {
    download_path: []const u8 = "/tmp/",
    extract_path: []const u8 = "/tmp/",
};

const PackageFromSource = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    version: []const u8,
    release: []const u8,
    source: []const u8,
    url: []const u8,
    license: []const u8,
    build_script: []const u8,
    build_options: BuildOptions,

    const License = union(enum) {
        mit,
        custom: []const u8,
    };

    fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        description: []const u8,
        version: []const u8,
        release: []const u8,
        source: []const u8,
        url: []const u8,
        license: License,
        license_custom: []const u8,
        build_script: []const u8,
        build_options: BuildOptions,
    ) !PackageFromSource {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .description = try allocator.dupe(u8, description),
            .version = try allocator.dupe(u8, version),
            .release = try allocator.dupe(u8, release),
            .source = try allocator.dupe(u8, source),
            .url = try allocator.dupe(u8, url),
            .license = license,
            .license_custom = try allocator.dupe(u8, license_custom),
            .build_script = try allocator.dupe(u8, build_script),
            .build_options = build_options,
        };
    }

    fn deinit(self: *PackageFromSource) void {
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        self.allocator.free(self.version);
        self.allocator.free(self.release);
        self.allocator.free(self.source);
        self.allocator.free(self.url);
        self.allocator.free(self.license_custom);
        self.allocator.free(self.build_script);
    }

    fn fetch(self: *PackageFromSource) !void {
        std.log.info("Fetching {s}...", .{self.source});
        var downloader = Downloader.init(self.allocator, self.source);
        defer downloader.deinit();
        if (try downloader.download() != .ok) return error.DownloadFailed;

        var filename: std.ArrayListUnmanaged(u8) = .{};
        defer filename.deinit(self.allocator);
        try filename.appendSlice(self.allocator, self.name);
        try filename.append(self.allocator, '-');
        try filename.appendSlice(self.allocator, self.version);
        try filename.appendSlice(self.allocator, ".tar.gz");

        var dir = try std.fs.openDirAbsolute("/tmp", .{});
        defer dir.close();
        var file = try dir.createFile(filename.items, .{});
        defer file.close();
        try file.writeAll(downloader.storage.items);
    }

    fn extract(self: *PackageFromSource) !void {
        std.log.info("Unpacking into {s}...", .{self.build_options});
        var input_filename: std.ArrayListUnmanaged(u8) = .{};
        defer input_filename.deinit(self.allocator);
        try input_filename.appendSlice(self.allocator, self.name);
        try input_filename.append(self.allocator, '-');
        try input_filename.appendSlice(self.allocator, self.version);
        try input_filename.appendSlice(self.allocator, ".tar.gz");

        var read_dir = try std.fs.openDirAbsolute("/tmp", .{});
        defer read_dir.close();
        var read_file = try read_dir.openFile(input_filename.items, .{});
        defer read_file.close();

        var tar = std.ArrayList(u8).init(self.allocator);
        defer tar.deinit();

        var buffered_reader = std.io.bufferedReader(read_file.reader());
        const file_reader = buffered_reader.reader();
        try std.compress.gzip.decompress(file_reader, tar.writer());

        var fixed_buffer_stream = std.io.fixedBufferStream(tar.items);
        const tar_reader = fixed_buffer_stream.reader();
        var output_dir_path: std.ArrayListUnmanaged(u8) = .{};
        defer output_dir_path.deinit(self.allocator);
        try output_dir_path.appendSlice(self.allocator, "/tmp/");
        try output_dir_path.appendSlice(self.allocator, self.name);
        try output_dir_path.append(self.allocator, '-');
        try output_dir_path.appendSlice(self.allocator, self.version);
        try std.fs.deleteTreeAbsolute(output_dir_path.items);
        try std.fs.makeDirAbsolute(output_dir_path.items);
        const output_dir = try std.fs.openDirAbsolute(output_dir_path.items, .{});
        try std.tar.pipeToFileSystem(output_dir, tar_reader, .{ .strip_components = 1 });
    }

    fn build(self: *PackageFromSource) !void {
        _ = options;
        var cwd: std.ArrayListUnmanaged(u8) = .{};
        defer cwd.deinit(self.allocator);
        try cwd.appendSlice(self.allocator, "/tmp/");
        try cwd.appendSlice(self.allocator, self.name);
        try cwd.append(self.allocator, '-');
        try cwd.appendSlice(self.allocator, self.version);

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = .{ "bash", "-e", self.build_script },
            .cwd = cwd.items,
        });
    }

    fn validateName(self: PackageFromSource) error.InvalidName!void {
        for (self.name) |c| switch (c) {
            'a'...'z', '1'...'0', '-' => {},
            else => {
                return error.InvalidName;
            },
        };
    }

    fn validateVersion(self: PackageFromSource) error.InvalidVersion!void {
        for (self.name) |c| switch (c) {
            'a'...'z', 'A'...'Z', '1'...'0', '.', '_' => {},
            else => {
                return error.InvalidVersion;
            },
        };
    }
};

test {
    var package = try PackageFromSource.init(
        std.testing.allocator,
        "hello-test",
        "A hello world project for fun and profit",
        "1.0.0",
        "1",
        "https://github.com/em-dash/hello-test/archive/refs/tags/v1.0.0.tar.gz",
        "https://github.com/em-dash/hello-test",
        .mit,
        "",
        \\zig build -Dcpu=baseline -Doptimize=ReleaseFast -Dtarget=x86_64-linux
    ,
        .{},
    );

    defer package.deinit();

    try package.fetch();
    try package.extract();
    try package.build(.{});
}

const std = @import("std");
