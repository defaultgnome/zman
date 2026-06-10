const std = @import("std");
const zman = @import("zman");

pub fn printTaskLog(writer: anytype, task: zman.StoreMut.TaskMut) !void {
    var total_buf: [32]u8 = undefined;
    const total = zman.formatDurationSeconds(zman.taskTotalSeconds(task.times.items), &total_buf);
    try writer.print("Task: {s}\nTotal: {s}\n\n", .{ task.name, total });

    const col_start = "Clock-in";
    const col_end = "Clock-out";
    const col_dur = "Duration";

    var start_w: usize = col_start.len;
    var end_w: usize = col_end.len;
    var dur_w: usize = col_dur.len;

    for (task.times.items) |entry| {
        var start_buf: [32]u8 = undefined;
        var end_buf: [32]u8 = undefined;
        var dur_buf: [32]u8 = undefined;
        start_w = @max(start_w, entryDisplayStart(entry, &start_buf).len);
        end_w = @max(end_w, entryDisplayEnd(entry, &end_buf).len);
        dur_w = @max(dur_w, entryDisplayDuration(entry, &dur_buf).len);
    }

    try printRow(writer, start_w, end_w, dur_w, col_start, col_end, col_dur);

    for (task.times.items) |entry| {
        var start_buf: [32]u8 = undefined;
        var end_buf: [32]u8 = undefined;
        var dur_buf: [32]u8 = undefined;
        try printRow(
            writer,
            start_w,
            end_w,
            dur_w,
            entryDisplayStart(entry, &start_buf),
            entryDisplayEnd(entry, &end_buf),
            entryDisplayDuration(entry, &dur_buf),
        );
    }
}

fn entryDisplayStart(entry: zman.TaskTimeEntry, buf: *[32]u8) []const u8 {
    return zman.formatTimestampOpt(entry.start, buf);
}

fn entryDisplayEnd(entry: zman.TaskTimeEntry, buf: *[32]u8) []const u8 {
    return zman.formatTimestampOpt(entry.end, buf);
}

fn entryDisplayDuration(entry: zman.TaskTimeEntry, buf: *[32]u8) []const u8 {
    if (entry.start) |start| {
        if (entry.end) |end| {
            const secs: u64 = if (end >= start) @intCast(end - start) else 0;
            return zman.formatDurationSeconds(secs, buf);
        }
    }
    return zman.na_label;
}

fn printRow(
    writer: anytype,
    start_w: usize,
    end_w: usize,
    dur_w: usize,
    start: []const u8,
    end: []const u8,
    dur: []const u8,
) !void {
    try padPrint(writer, start, start_w);
    try writer.writeAll("  ");
    try padPrint(writer, end, end_w);
    try writer.writeAll("  ");
    try padPrint(writer, dur, dur_w);
    try writer.writeAll("\n");
}

fn padPrint(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    var pad = width - text.len;
    while (pad > 0) : (pad -= 1) try writer.writeAll(" ");
}
