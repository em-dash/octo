pub fn allAreAlphabetic(string: []const u8) bool {
    for (string) |c| if (!std.ascii.isAlphabetic(c)) return false;
    return true;
}

const UriScheme = enum {
    http,
    https,
    ftp,
};

pub fn fetchUri(
    allocator: std.mem.Allocator,
    uri: std.Uri,
) ![]const u8 {
    var storage = std.ArrayList(u8).init(allocator);
    defer storage.deinit();
    var uri_string = std.ArrayList(u8).init(allocator);
    defer uri_string.deinit();
    try uri.writeToStream(.{
        .scheme = true,
        .authority = true,
        .path = true,
        .query = true,
        .fragment = true,
    }, uri_string.writer());

    if (std.meta.stringToEnum(UriScheme, uri.scheme)) |e| switch (e) {
        .http, .https, .ftp => {
            var client = std.http.Client{ .allocator = allocator };
            defer client.deinit();

            const result = try client.fetch(.{
                .location = .{ .url = uri_string.items },
                .redirect_behavior = @enumFromInt(5),
                .response_storage = .{ .dynamic = &storage },
            });
            if (result.status != .ok) return error.BadStatus;
        },
    } else {
        return error.UnknownUriScheme;
    }

    return try storage.toOwnedSlice();
}

pub const ArchiveType = enum {
    @".tar.gz",
    @".tar.xz",
    @".zip",

    pub fn fromPath(path: []const u8) ?ArchiveType {
        inline for (@typeInfo(ArchiveType).@"enum".fields) |f|
            if (std.mem.endsWith(u8, path, f.name)) return @enumFromInt(f.value);
        return null;
    }
};

const std = @import("std");
