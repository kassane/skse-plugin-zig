//! The game's in-game console.
//!
//! CommonLib's `RE::ConsoleLog` pairs the file logger with this: `Print` is a
//! variadic member that builds a `va_list` and hands it to `VPrint`, so one
//! call puts a finished line on the `~` screen. Both addresses below are the
//! 1.7.104 image's, as address-library ids of the AE pair in
//! `RELOCATION_ID(se, ae)`.

const std = @import("std");
const builtin = @import("builtin");
const game = @import("game.zig");

/// `ConsoleLog**`, the global behind `RE::ConsoleLog::GetSingleton`.
const singleton_rva = 0x031DFB70;
/// `ConsoleLog::Print(const char*, ...)` (address-library id 51109; its
/// `VPrint` callee is 51110).
const print_rva = 0x0090F1B0;

const PrintFn = *const fn (*anyopaque, [*:0]const u8, ...) callconv(.c) void;

/// Whether `val` was known at compile time, which decides whether the line
/// gets baked into the binary or formatted per call.
inline fn isComptime(val: anytype) bool {
    return @typeInfo(@TypeOf(.{val})).@"struct".field_attrs[0].@"comptime";
}

/// Write one formatted line to the console. Nothing happens when the
/// singleton is absent; the guard also keeps a host test build from
/// reaching kernel32.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (builtin.os.tag != .windows) return;

    const holder: *?*anyopaque = @ptrFromInt(game.base() + singleton_rva);
    const console = holder.* orelse return;

    // A trailing newline would only add a blank row on screen, so it is
    // dropped from the format itself: the trimmed format keeps its own
    // sentinel directly after the text.
    const line_fmt = comptime std.mem.trimEnd(u8, fmt, "\n");

    if (isComptime(args)) {
        game.fnAt(print_rva, PrintFn)(console, "%s", std.fmt.comptimePrint(line_fmt, args).ptr);
    } else {
        var buf: [1024]u8 = undefined;
        const filled = std.fmt.bufPrintSentinel(&buf, line_fmt, args, 0) catch return;
        game.fnAt(print_rva, PrintFn)(console, "%s", filled.ptr);
    }
}
