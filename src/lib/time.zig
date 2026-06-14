const std = @import("std");
const Io = std.Io;
const local_time = @import("local_time.zig");
const time_epoch = std.time.epoch;

pub const na_label = "N/A";

pub const TaskTimeEntry = struct {
    start: ?i64 = null,
    end: ?i64 = null,
};

pub fn unixNow(io: Io) i64 {
    const ts = Io.Timestamp.now(io, .real);
    return @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
}

pub fn formatDurationSeconds(seconds: u64, buf: *[32]u8) []const u8 {
    const hours = seconds / std.time.s_per_hour;
    const minutes = (seconds % std.time.s_per_hour) / std.time.s_per_min;
    const secs = seconds % std.time.s_per_min;
    return std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2}", .{ hours, minutes, secs }) catch unreachable;
}

pub fn formatTimestamp(epoch: i64, buf: *[32]u8) []const u8 {
    const local = local_time.fromUnixEpoch(epoch);
    return std.fmt.bufPrint(buf, "{d:04}-{d:02}-{d:02} {d:02}:{d:02}:{d:02}", .{
        @as(u16, @intCast(local.year)),
        @as(u4, @intCast(local.month)),
        @as(u5, @intCast(local.day)),
        @as(u5, @intCast(local.hour)),
        @as(u6, @intCast(local.minute)),
        @as(u6, @intCast(local.second)),
    }) catch unreachable;
}

pub fn formatTimestampOpt(epoch: ?i64, buf: *[32]u8) []const u8 {
    if (epoch) |e| return formatTimestamp(e, buf);
    return na_label;
}

pub fn timeEntryEnd(entry: TaskTimeEntry) i64 {
    return entry.end orelse std.math.maxInt(i64);
}

pub fn timesOverlap(a: TaskTimeEntry, b: TaskTimeEntry) bool {
    const a_start = a.start orelse return false;
    const b_start = b.start orelse return false;
    return a_start < timeEntryEnd(b) and b_start < timeEntryEnd(a);
}

pub fn taskTotalSeconds(times: []const TaskTimeEntry) u64 {
    var total: u64 = 0;
    for (times) |entry| {
        if (entry.start) |start| {
            if (entry.end) |end| {
                if (end >= start) total += @intCast(end - start);
            }
        }
    }
    return total;
}

/// Parse a user-supplied time string into a unix timestamp (stored as UTC epoch).
///
/// All parsed values are interpreted in the system's local timezone.
///
/// Supported formats:
/// - `HH:MM` or `HH:MM:SS` — today in local time
/// - `YYYY-MM-DD HH:MM` or `YYYY-MM-DD HH:MM:SS`
/// - `YYYY-MM-DDTHH:MM` or `YYYY-MM-DDTHH:MM:SS`
pub fn parseTimeSpecifier(text: []const u8, now_epoch: i64) !i64 {
    const trimmed = std.mem.trim(u8, text, " \t\"'");

    if (std.mem.indexOfScalar(u8, trimmed, '-')) |_| {
        return try parseDateTime(trimmed);
    }

    const clock = try parseClock(trimmed);
    const local_now = local_time.fromUnixEpoch(now_epoch);
    return try local_time.toUnixEpoch(.{
        .year = local_now.year,
        .month = local_now.month,
        .day = local_now.day,
        .hour = clock.hour,
        .minute = clock.minute,
        .second = clock.second,
    });
}

fn parseDateTime(text: []const u8) !i64 {
    const date_end = std.mem.indexOfScalar(u8, text, ' ') orelse
        std.mem.indexOfScalar(u8, text, 'T') orelse return error.InvalidTimeFormat;
    const date_part = text[0..date_end];
    const time_part = std.mem.trim(u8, text[date_end + 1 ..], " \t");

    const date = try parseDate(date_part);
    const clock = try parseClock(time_part);
    return try local_time.toUnixEpoch(.{
        .year = date.year,
        .month = date.month,
        .day = date.day,
        .hour = clock.hour,
        .minute = clock.minute,
        .second = clock.second,
    });
}

const ParsedDate = struct {
    year: i32,
    month: i32,
    day: i32,
};

fn parseDate(text: []const u8) !ParsedDate {
    var parts = std.mem.splitScalar(u8, text, '-');
    const year_text = parts.next() orelse return error.InvalidTimeFormat;
    const month_text = parts.next() orelse return error.InvalidTimeFormat;
    const day_text = parts.next() orelse return error.InvalidTimeFormat;
    if (parts.next() != null) return error.InvalidTimeFormat;

    const year: i32 = try std.fmt.parseInt(i32, year_text, 10);
    const month: i32 = try std.fmt.parseInt(i32, month_text, 10);
    if (month < 1 or month > 12) return error.InvalidTimeFormat;

    const day: i32 = try std.fmt.parseInt(i32, day_text, 10);
    const month_enum: time_epoch.Month = @enumFromInt(@as(u4, @intCast(month)));
    if (day < 1 or day > getDaysInMonth(@intCast(year), month_enum)) return error.InvalidTimeFormat;

    return .{ .year = year, .month = month, .day = day };
}

const ParsedClock = struct {
    hour: i32,
    minute: i32,
    second: i32,
};

fn parseClock(text: []const u8) !ParsedClock {
    var parts = std.mem.splitScalar(u8, text, ':');
    const hour_text = parts.next() orelse return error.InvalidTimeFormat;
    const minute_text = parts.next() orelse return error.InvalidTimeFormat;
    const second_text = parts.next();
    if (parts.next() != null) return error.InvalidTimeFormat;

    const hour: i32 = try std.fmt.parseInt(i32, hour_text, 10);
    const minute: i32 = try std.fmt.parseInt(i32, minute_text, 10);
    const second: i32 = if (second_text) |sec_text|
        try std.fmt.parseInt(i32, sec_text, 10)
    else
        0;

    if (hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 59) {
        return error.InvalidTimeFormat;
    }

    return .{ .hour = hour, .minute = minute, .second = second };
}

fn getDaysInMonth(year: time_epoch.Year, month: time_epoch.Month) u5 {
    return time_epoch.getDaysInMonth(year, month);
}

test formatDurationSeconds {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0:00:01", formatDurationSeconds(1, &buf));
    try std.testing.expectEqualStrings("1:02:03", formatDurationSeconds(3723, &buf));
}

test timesOverlap {
    const closed = TaskTimeEntry{ .start = 100, .end = 200 };
    const overlap = TaskTimeEntry{ .start = 150, .end = 250 };
    const adjacent = TaskTimeEntry{ .start = 200, .end = 300 };
    const open = TaskTimeEntry{ .start = 180, .end = null };
    const orphan = TaskTimeEntry{ .start = null, .end = 150 };

    try std.testing.expect(timesOverlap(closed, overlap));
    try std.testing.expect(!timesOverlap(closed, adjacent));
    try std.testing.expect(timesOverlap(closed, open));
    try std.testing.expect(!timesOverlap(closed, orphan));
}

test taskTotalSeconds {
    const times = [_]TaskTimeEntry{
        .{ .start = 100, .end = 160 },
        .{ .start = 200, .end = null },
        .{ .start = 300, .end = 450 },
        .{ .start = null, .end = 500 },
    };
    try std.testing.expectEqual(@as(u64, 210), taskTotalSeconds(&times));
}

test parseTimeSpecifier {
    local_time.testingSetUtcTimezone();

    const now = 1_718_366_400; // 2024-06-14 12:00:00 local (TZ=UTC)
    try std.testing.expectEqual(
        @as(i64, 1_718_359_200),
        try parseTimeSpecifier("10:00", now),
    );
    try std.testing.expectEqual(
        @as(i64, 1_718_359_230),
        try parseTimeSpecifier("10:00:30", now),
    );
    try std.testing.expectEqual(
        @as(i64, 1_718_359_200),
        try parseTimeSpecifier("2024-06-14 10:00", now),
    );
    try std.testing.expectEqual(
        @as(i64, 1_718_359_230),
        try parseTimeSpecifier("2024-06-14T10:00:30", now),
    );
}

test "formatTimestamp uses local timezone" {
    local_time.testingSetUtcTimezone();

    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2024-06-14 12:00:00",
        formatTimestamp(1_718_366_400, &buf),
    );
}
