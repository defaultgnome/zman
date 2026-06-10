const std = @import("std");
const Io = std.Io;

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
    const secs: u64 = @intCast(@max(epoch, 0));
    const epoch_sec = std.time.epoch.EpochSeconds{ .secs = secs };
    const day_sec = epoch_sec.getDaySeconds();
    const year_day = epoch_sec.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.bufPrint(buf, "{d:04}-{d:02}-{d:02} {d:02}:{d:02}:{d:02}", .{
        year_day.year, @intFromEnum(month_day.month), month_day.day_index + 1,
        day_sec.getHoursIntoDay(), day_sec.getMinutesIntoHour(), day_sec.getSecondsIntoMinute(),
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
