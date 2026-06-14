const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const posix = std.posix;

pub const TimerInput = struct {
    stdin_fd: posix.fd_t,
    saved_termios: ?posix.termios = null,
    saved_console_mode: ?u32 = null,

    pub fn init() !TimerInput {
        const stdin = Io.File.stdin();
        var self = TimerInput{ .stdin_fd = stdin.handle };

        if (builtin.os.tag == .windows) {
            self.saved_console_mode = try windowsConsoleGetMode(stdin.handle);
            const mode = self.saved_console_mode.? &
                ~@as(u32, ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
            try windowsConsoleSetMode(stdin.handle, mode);
            return self;
        }

        var termios = try posix.tcgetattr(self.stdin_fd);
        self.saved_termios = termios;
        termios.lflag.ICANON = false;
        termios.lflag.ECHO = false;
        termios.cc[@intFromEnum(posix.V.MIN)] = 0;
        termios.cc[@intFromEnum(posix.V.TIME)] = 0;
        try posix.tcsetattr(self.stdin_fd, .FLUSH, termios);
        return self;
    }

    pub fn deinit(self: *TimerInput) void {
        if (builtin.os.tag == .windows) {
            if (self.saved_console_mode) |mode| {
                windowsConsoleSetMode(self.stdin_fd, mode) catch {};
            }
            return;
        }

        if (self.saved_termios) |termios| {
            posix.tcsetattr(self.stdin_fd, .FLUSH, termios) catch {};
        }
    }

    pub fn escapePressed(self: TimerInput) bool {
        if (builtin.os.tag == .windows) return windowsEscapePressed(self.stdin_fd);
        return posixEscapePressed(self.stdin_fd);
    }
};

fn posixEscapePressed(fd: posix.fd_t) bool {
    var fds = [_]posix.pollfd{.{
        .fd = fd,
        .events = posix.POLL.IN,
        .revents = undefined,
    }};
    const ready = posix.poll(&fds, 0) catch return false;
    if (ready == 0) return false;

    var buf: [32]u8 = undefined;
    const read_count = posix.read(fd, &buf) catch return false;
    for (buf[0..read_count]) |byte| {
        if (byte == 0x1b) return true;
    }
    return false;
}

const ENABLE_LINE_INPUT: u32 = 0x0002;
const ENABLE_ECHO_INPUT: u32 = 0x0004;

const windows = std.os.windows;

const INPUT_RECORD = extern struct {
    EventType: windows.WORD,
    Event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
        _: [16]u8,
    },
};

const KEY_EVENT_RECORD = extern struct {
    bKeyDown: windows.BOOL,
    wRepeatCount: windows.WORD,
    wVirtualKeyCode: windows.WORD,
    wVirtualScanCode: windows.WORD,
    uChar: extern union {
        UnicodeChar: windows.WCHAR,
        AsciiChar: windows.CHAR,
    },
    dwControlKeyState: windows.DWORD,
};

const INPUT_EVENT_KEY: windows.WORD = 0x0001;
const VK_ESCAPE: windows.WORD = 0x001B;

extern "kernel32" fn GetConsoleMode(
    hConsoleHandle: windows.HANDLE,
    lpMode: *windows.DWORD,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn SetConsoleMode(
    hConsoleHandle: windows.HANDLE,
    dwMode: windows.DWORD,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn PeekConsoleInputW(
    hConsoleInput: windows.HANDLE,
    lpBuffer: [*]INPUT_RECORD,
    nLength: windows.DWORD,
    lpNumberOfEventsRead: *windows.DWORD,
) callconv(.winapi) windows.BOOL;

fn windowsConsoleGetMode(handle: posix.fd_t) !u32 {
    var mode: windows.DWORD = undefined;
    if (GetConsoleMode(handle, &mode) == 0) return error.NotConsole;
    return mode;
}

fn windowsConsoleSetMode(handle: posix.fd_t, mode: u32) !void {
    if (SetConsoleMode(handle, mode) == 0) return error.NotConsole;
}

fn windowsEscapePressed(handle: posix.fd_t) bool {
    var records: [16]INPUT_RECORD = undefined;
    var read_count: windows.DWORD = undefined;
    if (PeekConsoleInputW(handle, &records, records.len, &read_count) == 0) return false;

    var event_index: usize = 0;
    while (event_index < read_count) : (event_index += 1) {
        const record = records[event_index];
        if (record.EventType != INPUT_EVENT_KEY) continue;
        const key = record.Event.KeyEvent;
        if (key.bKeyDown == 0) continue;
        if (key.wVirtualKeyCode == VK_ESCAPE) return true;
    }
    return false;
}
