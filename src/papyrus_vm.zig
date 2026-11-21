//! The VM side of a native call: frame arguments, arrays, registration.
//! RVAs are the 1.7.104 image's.

const game = @import("game.zig");
const value = @import("papyrus_value.zig");

/// One C++ vtable entry; an object's first word points at an array of these.
pub const Slot = *const anyopaque;

/// `BSScript::VMArgList`, touched only through its two game functions.
pub const VMArgList = opaque {};

/// The running frame; only its first word (`arg_list`) is read.
pub const VMState = extern struct {
    arg_list: *VMArgList,
};

/// `BSScript::Internal::VirtualMachine`, the object SKSE hands a Papyrus callback.
pub const VirtualMachine = extern struct {
    vptr: [*]Slot,

    /// `BindNativeMethod`, slot 24 (`call [rax+0xc0]` in the game's loop); returns nothing.
    const bind_native_method_slot = 24;

    /// `CreateArray`, slot 22 (0xB0).
    const create_array_slot = 22;

    pub fn bindNativeMethod(self: *VirtualMachine, function: *anyopaque) void {
        const slot: *const fn (*VirtualMachine, *anyopaque) callconv(.c) void =
            @ptrFromInt(@intFromPtr(self.vptr[bind_native_method_slot]));
        slot(self, function);
    }

    /// `CreateArray`: writes the `Array*` into `out` (a `BSTSmartPointer`, one
    /// pointer, NOT a `VMValue`); the caller builds `{arrayOf(element), pointer}`.
    /// Fresh count 2 (creator + VM tracking): `assign` the result, `reset` the
    /// creator's. False only on allocation failure.
    pub fn createArray(self: *VirtualMachine, element_type: *const value.TypeInfo, size: u32, out: *?*anyopaque) bool {
        const slot: *const fn (*VirtualMachine, *const value.TypeInfo, u32, *?*anyopaque) callconv(.c) bool =
            @ptrFromInt(@intFromPtr(self.vptr[create_array_slot]));
        return slot(self, element_type, size, out);
    }
};

const GetOffsetFn = *const fn (*VMArgList, *VMState) callconv(.c) u32;
const GetFn = *const fn (*VMArgList, *VMState, u32, u32) callconv(.c) ?*value.VMValue;

/// `VMArgList::GetOffset` (RVA `0x0149E7F0`): read once per call, pass to every `getArg`.
pub fn getOffset(state: *VMState) u32 {
    return game.fnAt(0x0149E7F0, GetOffsetFn)(state.arg_list, state);
}

/// `VMArgList::Get` (RVA `0x0149E860`): one argument's cell, null if absent.
pub fn getArg(state: *VMState, index: u32, offset: u32) ?*value.VMValue {
    return game.fnAt(0x0149E860, GetFn)(state.arg_list, state, index, offset);
}

test "a frame reaches its argument list through offset 0x00" {
    const std = @import("std");
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(VMState, "arg_list"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(*VMArgList));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(VirtualMachine, "vptr"));
    // The game's registration loop calls `BindNativeMethod` at `call [rax+0xc0]`.
    try std.testing.expectEqual(@as(usize, 0xc0), VirtualMachine.bind_native_method_slot * 8);
    try std.testing.expectEqual(@as(usize, 0xb0), VirtualMachine.create_array_slot * 8);
}
