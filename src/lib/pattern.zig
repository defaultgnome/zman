const std = @import("std");

/// Glob match with `*` matching any substring (including empty).
pub fn matchesPattern(pattern: []const u8, text: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    return matchAt(pattern, text, 0, 0);
}

fn matchAt(pattern: []const u8, text: []const u8, pi: usize, ti: usize) bool {
    if (pi == pattern.len) return ti == text.len;
    if (pattern[pi] == '*') {
        var ti_scan = ti;
        while (true) : (ti_scan += 1) {
            if (matchAt(pattern, text, pi + 1, ti_scan)) return true;
            if (ti_scan > text.len) break;
        }
        return false;
    }
    if (ti >= text.len or pattern[pi] != text[ti]) return false;
    return matchAt(pattern, text, pi + 1, ti + 1);
}

test matchesPattern {
    try std.testing.expect(matchesPattern("*", "anything"));
    try std.testing.expect(matchesPattern("foo", "foo"));
    try std.testing.expect(!matchesPattern("foo", "bar"));
    try std.testing.expect(matchesPattern("foo*", "foobar"));
    try std.testing.expect(matchesPattern("*bar", "foobar"));
    try std.testing.expect(matchesPattern("f*o", "fizzbuzzo"));
}
