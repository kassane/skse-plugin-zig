//! The VM side of one native call: reading the arguments the frame carries and
//! handing a finished function to the registry.
//!
//! Everything here resolves at run time from RVAs in the 1.7.104 image.

const game = @import("game.zig");
const value = @import("papyrus_value.zig");

/// One entry of a C++ vtable. `IFunction` and `VMClassRegistry` are objects
/// whose first word points at an array of these, which is what makes them
/// reachable from Zig without a C++ compiler.
pub const Slot = *const anyopaque;

/// `BSScript::VMArgList`, touched only through its two game functions.
pub const VMArgList = opaque {};

/// The running frame. Only its first word at `0x00` is read here; the rest of
/// the object belongs to the VM and nothing in this package looks past it.
pub const VMState = extern struct {
    arg_list: *VMArgList,
};

/// `BSScript::VMClassRegistry`, the object SKSE hands a Papyrus plugin callback.
pub const Registry = extern struct {
    vptr: [*]Slot,

    /// `VMClassRegistry::RegisterFunction(IFunction*)`, slot `0x18`. The game's own
    /// registration loop reaches it as `call [rax+0xc0]` and ignores any result,
    /// because the slot returns nothing.
    const register_function_slot = 24;

    pub fn registerFunction(self: *Registry, function: *anyopaque) void {
        const call: *const fn (*Registry, *anyopaque) callconv(.c) void =
            @ptrFromInt(@intFromPtr(self.vptr[register_function_slot]));
        call(self, function);
    }
};

const GetOffsetFn = *const fn (*VMArgList, *VMState) callconv(.c) u32;
const GetFn = *const fn (*VMArgList, *VMState, u32, u32) callconv(.c) ?*value.VMValue;

/// `VMArgList::GetOffset` (RVA `0x0149E7F0`): where this frame's arguments
/// begin. It has to be read once per call and passed to every `getArg`.
pub fn getOffset(state: *VMState) u32 {
    return game.fnAt(0x0149E7F0, GetOffsetFn).*(state.arg_list, state);
}

/// `VMArgList::Get` (RVA `0x0149E860`): the cell for one argument. The frame
/// holds no such argument when this returns null.
pub fn getArg(state: *VMState, index: u32, offset: u32) ?*value.VMValue {
    return game.fnAt(0x0149E860, GetFn).*(state.arg_list, state, index, offset);
}

test "a frame reaches its argument list through offset 0x00" {
    const std = @import("std");
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(VMState, "arg_list"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(*VMArgList));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Registry, "vptr"));
    // The game's registration loop calls `RegisterFunction` at `call [rax+0xc0]`.
    try std.testing.expectEqual(@as(usize, 0xc0), Registry.register_function_slot * 8);
}
