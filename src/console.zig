//! The game's `~` console via `RE::ConsoleLog`. `Print` is variadic and hands
//! a `va_list` to `VPrint`. Addresses are the 1.7.104 AE half of
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

/// Whether `val` is comptime: bake the line, or format per call.
inline fn isComptime(val: anytype) bool {
    return @typeInfo(@TypeOf(.{val})).@"struct".field_attrs[0].@"comptime";
}

/// Write one line to the console; no-op if the singleton is absent (also keeps
/// host test builds off kernel32).
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (builtin.os.tag != .windows) return;

    const holder: *?*anyopaque = @ptrFromInt(game.base() + singleton_rva);
    const console = holder.* orelse return;

    // Drop a trailing newline (it would add a blank row); keep the sentinel.
    const line_fmt = comptime std.mem.trimEnd(u8, fmt, "\n");

    if (isComptime(args)) {
        game.fnAt(print_rva, PrintFn)(console, "%s", std.fmt.comptimePrint(line_fmt, args).ptr);
    } else {
        var buf: [1024]u8 = undefined;
        const filled = std.fmt.bufPrintSentinel(&buf, line_fmt, args, 0) catch return;
        game.fnAt(print_rva, PrintFn)(console, "%s", filled.ptr);
    }
}
