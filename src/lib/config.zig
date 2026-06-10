const std = @import("std");
const Io = std.Io;
const known_folders = @import("known_folders");

pub const store_filename = "zman.json";

pub fn configDirPath(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
) ![]const u8 {
    return try known_folders.getPath(io, allocator, environ, .local_configuration) orelse error.ConfigFolderUnavailable;
}

pub fn configFilePath(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
) ![]const u8 {
    const config_path = try configDirPath(io, allocator, environ);
    defer allocator.free(config_path);
    return std.fs.path.join(allocator, &.{ config_path, store_filename });
}

pub fn openConfigDir(
    io: Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
) !Io.Dir {
    const config_path = try configDirPath(io, allocator, environ);
    defer allocator.free(config_path);
    return try Io.Dir.cwd().createDirPathOpen(io, config_path, .{});
}
