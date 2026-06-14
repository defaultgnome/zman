const std = @import("std");

const c = @cImport({
    @cInclude("time.h");
});

pub const CivilTime = struct {
    year: i32,
    month: i32,
    day: i32,
    hour: i32,
    minute: i32,
    second: i32,
};

pub fn fromUnixEpoch(epoch: i64) CivilTime {
    var ts: c.time_t = @intCast(epoch);
    var tm: c.struct_tm = undefined;

    if (@hasDecl(c, "localtime_s")) {
        if (c.localtime_s(&tm, &ts) != 0) unreachable;
    } else if (@hasDecl(c, "localtime_r")) {
        _ = c.localtime_r(&ts, &tm).?;
    } else {
        const ptr = c.localtime(&ts) orelse unreachable;
        tm = ptr.*;
    }

    return civilTimeFromC(&tm);
}

pub fn toUnixEpoch(time: CivilTime) !i64 {
    var tm: c.struct_tm = .{
        .tm_sec = @intCast(time.second),
        .tm_min = @intCast(time.minute),
        .tm_hour = @intCast(time.hour),
        .tm_mday = @intCast(time.day),
        .tm_mon = @intCast(time.month - 1),
        .tm_year = @intCast(time.year - 1900),
        .tm_wday = 0,
        .tm_yday = 0,
        .tm_isdst = -1,
    };

    const result = c.mktime(&tm);
    if (result == -1) return error.InvalidTimeFormat;
    return @intCast(result);
}

pub fn localDayStart(epoch: i64) !i64 {
    const local = fromUnixEpoch(epoch);
    return toUnixEpoch(.{
        .year = local.year,
        .month = local.month,
        .day = local.day,
        .hour = 0,
        .minute = 0,
        .second = 0,
    });
}

fn civilTimeFromC(tm: *const c.struct_tm) CivilTime {
    return .{
        .year = @intCast(tm.tm_year + 1900),
        .month = @intCast(tm.tm_mon + 1),
        .day = @intCast(tm.tm_mday),
        .hour = @intCast(tm.tm_hour),
        .minute = @intCast(tm.tm_min),
        .second = @intCast(tm.tm_sec),
    };
}

extern "c" fn tzset() void;

pub fn testingSetUtcTimezone() void {
    std.posix.setenv("TZ", "UTC0", 1) catch {};
    tzset();
}

test "unix epoch roundtrip" {
    testingSetUtcTimezone();

    const epoch: i64 = 1_718_366_400; // 2024-06-14 12:00:00 UTC
    const local = fromUnixEpoch(epoch);
    try std.testing.expectEqual(@as(i32, 2024), local.year);
    try std.testing.expectEqual(@as(i32, 6), local.month);
    try std.testing.expectEqual(@as(i32, 14), local.day);
    try std.testing.expectEqual(@as(i32, 12), local.hour);

    try std.testing.expectEqual(epoch, try toUnixEpoch(local));
}
