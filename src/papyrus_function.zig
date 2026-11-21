//! One Papyrus native, built by the game's `NativeFunction` constructor. Its
//! vtable leaves `HasCallback` and `Run` pure; this package copies the table and
//! replaces those two slots.

const std = @import("std");
const game = @import("game.zig");
pub const value = @import("papyrus_value.zig");
pub const vm = @import("papyrus_vm.zig");

/// SKSE's `PapyrusNativeFunctionDef` parameter cap.
pub const max_params = 10;

const slot_count = 23;
const has_callback_slot = 21;
const run_slot = 22;

/// `NativeFunction`'s vtable, as the constructor writes it at RVA `0x014AA122`.
const native_vtable_rva = 0x01B26CB8;
const heap_rva = 0x00CDE250;
const heap_global_rva = 0x0369A810;
const ctor_rva = 0x014AA0F0;

const HeapAllocateFn = *const fn (*anyopaque, usize, usize, u8) callconv(.c) ?*anyopaque;

/// `NativeFunction::NativeFunction(fnName, className, isStatic, numParams)`.
const CtorFn = *const fn (*Object, [*:0]const u8, [*:0]const u8, u8, u32) callconv(.c) void;

/// A native's declaration.
pub const Signature = struct {
    /// Owning script, as `ScriptName` spells it.
    class: [*:0]const u8,
    name: [*:0]const u8,
    /// One id per parameter, in script order.
    params: []const value.Type = &.{},
    ret: value.Type = .none,
};

/// One native. `args[0..count]` are the parameters (pointer + count, not a
/// slice, for the win64 ABI); `result` arrives as `none`. `machine` is the
/// running VM, needed for `createArray`.
pub const Callback = *const fn (args: [*]const value.VMValue, count: u32, machine: *vm.VirtualMachine, result: *value.VMValue) callconv(.c) void;

/// `StringCache::Ref`, filled by the constructor.
const Handle = extern struct {
    ref: ?*anyopaque,
};

/// One `VDescTable` entry: name + type.
const ParamDesc = extern struct {
    name: Handle,
    type: u64,
};

const DescTable = extern struct {
    data: ?[*]ParamDesc,
    num_params: u16,
    unk0a: u16,
    _pad: [4]u8,
};

/// `BSScript::NativeFunction`, 0x58 bytes (1.7.104). Offsets pinned by the test below.
const Object = extern struct {
    vptr: [*]vm.Slot,
    ref_count: u32,
    _pad0c: [4]u8,
    name: Handle,
    obj_name: Handle,
    state_name: Handle,
    ret_type: u64,
    params: DescTable,
    is_static: u8,
    _unk41: u8,
    is_latent: u8,
    _pad43: u8,
    user_flags: u32,
    doc: Handle,
    callback: ?*const anyopaque,
};

/// The 23 game slots with the two pure ones replaced, shared by all natives.
/// Built on first use, on the game thread, so the lazy flag needs no lock.
var native_slots: [slot_count]vm.Slot = undefined;
var native_slots_built = false;

fn slots() *[slot_count]vm.Slot {
    if (!native_slots_built) {
        const installed: *const [slot_count]vm.Slot = @ptrFromInt(game.base() + native_vtable_rva);
        native_slots = installed.*;
        native_slots[has_callback_slot] = @ptrCast(&hasCallback);
        native_slots[run_slot] = @ptrCast(&run);
        native_slots_built = true;
    }
    return &native_slots;
}

/// `Heap::Allocate` on `g_mainHeap` -- the heap the game frees the object from.
fn heapAllocate(size: usize) ?*anyopaque {
    const heap: *anyopaque = @ptrFromInt(game.base() + heap_global_rva);
    return game.fnAt(heap_rva, HeapAllocateFn)(heap, size, 0, 0);
}

/// `HasCallback`: `Impl_Invoke` asks before every call; a pure slot would fault.
fn hasCallback(this: *Object) callconv(.c) bool {
    return this.callback != null;
}

/// `Run`: (receiver, VM, stack id, result, frame). False only if the call failed.
fn run(
    this: *Object,
    base: *value.VMValue,
    machine: *vm.VirtualMachine,
    stack_id: u32,
    result: *value.VMValue,
    state: *vm.VMState,
) callconv(.c) bool {
    // Global natives carry a StaticFunctionTag, not a receiver; stack_id is
    // for the long callback signature this package does not build.
    _ = base;
    _ = stack_id;

    const callback: Callback = @ptrCast(this.callback orelse return true);
    const count = this.params.num_params;
    if (count > max_params) return false;

    var cells: [max_params]value.VMValue = undefined;
    const offset = vm.getOffset(state);
    for (0..count) |i| {
        const argument = vm.getArg(state, @intCast(i), offset);
        cells[i] = if (argument) |cell| cell.* else .{};
    }

    callback(&cells, count, machine, result);
    return true;
}

/// Build and bind one `Global Native` (the constructor is told it is static).
pub fn register(machine: *vm.VirtualMachine, signature: Signature, callback: Callback) !void {
    if (signature.params.len > max_params) return error.TooManyParams;

    const raw = heapAllocate(@sizeOf(Object)) orelse return error.OutOfMemory;
    const object: *Object = @ptrCast(@alignCast(raw));

    game.fnAt(ctor_rva, CtorFn)(object, signature.name, signature.class, 1, @intCast(signature.params.len));

    object.ret_type = @backingInt(signature.ret);
    // The parameter table ctor (RVA 0x014DCFF0) allocates nothing for zero
    // parameters, so the table is null and there is nothing to patch.
    if (signature.params.len > 0) {
        const parameters = object.params.data orelse return error.NoParamTable;
        for (signature.params, 0..) |type_id, index| {
            parameters[index].type = @backingInt(type_id);
        }
    }

    const boxed: *const anyopaque = @ptrCast(callback);
    object.callback = boxed;
    object.vptr = slots();

    machine.bindNativeMethod(object);
}

test "the object matches what the 1.7.104 constructor writes" {
    try std.testing.expectEqual(@as(usize, 0x58), @sizeOf(Object));
    try std.testing.expectEqual(@as(usize, 0x00), @offsetOf(Object, "vptr"));
    try std.testing.expectEqual(@as(usize, 0x08), @offsetOf(Object, "ref_count"));
    try std.testing.expectEqual(@as(usize, 0x10), @offsetOf(Object, "name"));
    try std.testing.expectEqual(@as(usize, 0x18), @offsetOf(Object, "obj_name"));
    try std.testing.expectEqual(@as(usize, 0x20), @offsetOf(Object, "state_name"));
    try std.testing.expectEqual(@as(usize, 0x28), @offsetOf(Object, "ret_type"));
    try std.testing.expectEqual(@as(usize, 0x30), @offsetOf(Object, "params"));
    try std.testing.expectEqual(
        @as(usize, 0x38),
        @offsetOf(Object, "params") + @offsetOf(DescTable, "num_params"),
    );
    try std.testing.expectEqual(@as(usize, 0x40), @offsetOf(Object, "is_static"));
    try std.testing.expectEqual(@as(usize, 0x44), @offsetOf(Object, "user_flags"));
    try std.testing.expectEqual(@as(usize, 0x48), @offsetOf(Object, "doc"));
    try std.testing.expectEqual(@as(usize, 0x50), @offsetOf(Object, "callback"));
    try std.testing.expectEqual(@as(usize, 0x10), @sizeOf(ParamDesc));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(ParamDesc, "type"));
}

test "the replaced slots sit where Impl_Invoke calls them" {
    try std.testing.expectEqual(@as(usize, 0xa8), has_callback_slot * 8);
    try std.testing.expectEqual(@as(usize, 0xb0), run_slot * 8);
    try std.testing.expectEqual(@as(usize, slot_count), 23);
}

test "a signature defaults to no parameters and no return" {
    const signature = Signature{ .class = "Example", .name = "Nothing" };
    try std.testing.expectEqual(@as(usize, 0), signature.params.len);
    try std.testing.expectEqual(value.Type.none, signature.ret);
}
