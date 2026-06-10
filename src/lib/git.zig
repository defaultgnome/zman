const std = @import("std");
const Io = std.Io;

pub fn gitBranchName(io: Io, allocator: std.mem.Allocator) ![]const u8 {
    const head = Io.Dir.cwd().readFileAlloc(io, ".git/HEAD", allocator, .limited(256)) catch return error.NotGitRepo;
    defer allocator.free(head);

    const trimmed = std.mem.trim(u8, head, " \t\n\r");
    if (!std.mem.startsWith(u8, trimmed, "ref: refs/heads/")) return error.NotGitRepo;

    const branch = trimmed["ref: refs/heads/".len..];
    if (branch.len == 0) return error.NotGitRepo;
    return try allocator.dupe(u8, branch);
}

test gitBranchName {
    // NOTE: only meaningful when run inside a git repo; skip in isolation.
    _ = gitBranchName;
}
