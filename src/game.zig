//! Addresses inside SkyrimSE.exe.
//!
//! The image is relocatable: DYNAMIC_BASE with 171302 relocations, so no
//! address can be baked into the plugin. A game function is the module base
//! plus an RVA taken from the 1.7.104 headers.

const std = @import("std");
const w = std.os.windows;

extern "kernel32" fn GetModuleHandleW(lp_module_name: ?[*:0]const u16) callconv(.winapi) ?w.HMODULE;

/// Executable base (null name = the process image).
pub fn base() usize {
    return @intFromPtr(GetModuleHandleW(null) orelse unreachable);
}

/// A game function as a callable address; call it directly (`.*` is
/// comptime-only in 0.18). `F` is the header's declaration.
///
///     game.fnAt(0x0149E7F0, *const fn (*VMArgList, *VMState) callconv(.c) u32)
pub fn fnAt(comptime rva: usize, comptime F: type) F {
    return @ptrFromInt(base() + rva);
}
