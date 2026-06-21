const std = @import("std");
const Io = std.Io;

const max_git_walk_depth = 256;
const git_dir_prefix = "gitdir: ";

pub fn gitBranchName(io: Io, allocator: std.mem.Allocator) ![]const u8 {
    const head_path = try findGitHeadPath(io, allocator);
    defer allocator.free(head_path);

    const head = Io.Dir.cwd().readFileAlloc(io, head_path, allocator, .limited(256)) catch return error.NotGitRepo;
    defer allocator.free(head);

    const trimmed = std.mem.trim(u8, head, " \t\n\r");
    if (!std.mem.startsWith(u8, trimmed, "ref: refs/heads/")) return error.NotGitRepo;

    const branch = trimmed["ref: refs/heads/".len..];
    if (branch.len == 0) return error.NotGitRepo;
    return try allocator.dupe(u8, branch);
}

fn findGitHeadPath(io: Io, allocator: std.mem.Allocator) ![]const u8 {
    var prefix = std.ArrayList(u8).empty;
    defer prefix.deinit(allocator);

    var depth: usize = 0;
    while (depth < max_git_walk_depth) : (depth += 1) {
        const git_rel = try gitDotGitRelativePath(allocator, prefix.items);
        defer allocator.free(git_rel);

        const git_stat = Io.Dir.cwd().statFile(io, git_rel, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try prefix.appendSlice(allocator, "../");
                continue;
            },
            else => return err,
        };

        const head_path = switch (git_stat.kind) {
            .directory => try std.fs.path.join(allocator, &.{ git_rel, "HEAD" }),
            .file => blk: {
                const git_dir = try resolveGitDirFromFile(io, allocator, git_rel);
                defer allocator.free(git_dir);
                break :blk try std.fs.path.join(allocator, &.{ git_dir, "HEAD" });
            },
            else => return error.NotGitRepo,
        };
        return head_path;
    }

    return error.NotGitRepo;
}

fn gitDotGitRelativePath(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
    if (prefix.len == 0) return try allocator.dupe(u8, ".git");
    return try std.fmt.allocPrint(allocator, "{s}.git", .{prefix});
}

fn resolveGitDirFromFile(io: Io, allocator: std.mem.Allocator, git_rel: []const u8) ![]const u8 {
    const contents = Io.Dir.cwd().readFileAlloc(io, git_rel, allocator, .limited(512)) catch return error.NotGitRepo;
    defer allocator.free(contents);

    const gitdir = parseGitDirPath(contents) orelse return error.NotGitRepo;
    if (std.fs.path.isAbsolute(gitdir)) return try allocator.dupe(u8, gitdir);

    const git_parent = std.fs.path.dirname(git_rel) orelse ".";
    return try std.fs.path.join(allocator, &.{ git_parent, gitdir });
}

fn parseGitDirPath(contents: []const u8) ?[]const u8 {
    var line_it = std.mem.splitScalar(u8, contents, '\n');
    while (line_it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (!std.mem.startsWith(u8, trimmed, git_dir_prefix)) continue;
        const gitdir = std.mem.trim(u8, trimmed[git_dir_prefix.len..], " \t\r");
        if (gitdir.len > 0) return gitdir;
    }
    return null;
}

test parseGitDirPath {
    try std.testing.expectEqualStrings(
        "/repo/.git/worktrees/feature",
        parseGitDirPath("gitdir: /repo/.git/worktrees/feature\n").?,
    );
    try std.testing.expectEqualStrings(
        "../.git/modules/sub",
        parseGitDirPath("gitdir: ../.git/modules/sub\n").?,
    );
    try std.testing.expect(parseGitDirPath("not a git file\n") == null);
}

test "gitBranchName resolves worktree gitdir file" {
    const testing_io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPathOpen(testing_io, "metadata", .{});
    try tmp.dir.writeFile(testing_io, .{ .sub_path = "metadata/HEAD", .data = "ref: refs/heads/my-feature\n" });

    const metadata_path = try tmp.dir.realPathFileAlloc(testing_io, "metadata", allocator);
    defer allocator.free(metadata_path);

    const gitdir_line = try std.fmt.allocPrint(allocator, "gitdir: {s}\n", .{metadata_path});
    defer allocator.free(gitdir_line);

    try tmp.dir.createDirPathOpen(testing_io, "workdir/sub", .{});
    try tmp.dir.writeFile(testing_io, .{ .sub_path = "workdir/.git", .data = gitdir_line });

    const sub_path = try tmp.dir.realPathFileAlloc(testing_io, "workdir/sub", allocator);
    defer allocator.free(sub_path);

    var orig_buf: [std.fs.max_path_bytes]u8 = undefined;
    const orig_ptr = std.c.getcwd(&orig_buf, orig_buf.len) orelse return error.getcwdFailed;
    const orig_cwd = std.mem.span(orig_ptr);

    try std.posix.chdir(sub_path);
    defer std.posix.chdir(orig_cwd) catch {};

    const branch = try gitBranchName(testing_io, allocator);
    defer allocator.free(branch);
    try std.testing.expectEqualStrings("my-feature", branch);
}

test gitBranchName {
    // NOTE: only meaningful when run inside a git repo; skip in isolation.
    _ = gitBranchName;
}
