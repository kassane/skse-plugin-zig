//! One Papyrus native, assembled the way the game assembles its own.
//!
//! The game's `NativeFunction` constructor does the awkward work: it owns the
//! name handles, lays out the parameter description table and installs a
//! vtable. That vtable leaves `HasCallback` and `Run` pure, so this package
//! copies it and replaces exactly those two slots.

const std = @import("std");
const game = @import("game.zig");
pub const value = @import("papyrus_value.zig");
pub const vm = @import("papyrus_vm.zig");

/// SKSE's `PapyrusNativeFunctionDef` refuses to build a native with more
/// parameters than this.
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

/// What the VM has to know about a native before a call can reach it.
pub const Signature = struct {
    /// The script the function belongs to, as `ScriptName` spells it.
    class: [*:0]const u8,
    name: [*:0]const u8,
    /// One id per parameter, in script order.
    params: []const value.Type = &.{},
    ret: value.Type = .none,
};

/// One native implementation. The first `count` cells of `args` are the
/// declared parameters and `result` arrives as `none`, ready to be written.
/// A slice cannot cross the win64 ABI, so the parameters travel as a pointer
/// and a count.
pub const Callback = *const fn (args: [*]const value.VMValue, count: u32, result: *value.VMValue) callconv(.c) void;

/// `StringCache::Ref`, eight bytes the constructor fills in for us.
const Handle = extern struct {
    ref: ?*anyopaque,
};

/// One `VDescTable` entry: the name the VM reports and the type it checks.
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

/// `BSScript::NativeFunction`, `0x58` bytes of the 1.7.104 layout. Every offset
/// below is one the constructor writes; the test at the bottom pins them.
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

/// The 23 game slots with the two pure ones replaced. All natives built here
/// share it: only those two entries ever differ, and the installed table lives
/// in read-only `.rdata`. Built on first use, which happens on the game thread
/// inside the VM callback, so the lazy flag needs no synchronization.
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

/// `Heap::Allocate(size, alignment, aligned)` with `g_mainHeap` as its `this`,
/// the allocator `NativeFunction` declares through `DEFINE_STATIC_HEAP`. The
/// game frees the object from the same heap, so this is not an interchangeable
/// choice.
fn heapAllocate(size: usize) ?*anyopaque {
    const heap: *anyopaque = @ptrFromInt(game.base() + heap_global_rva);
    return game.fnAt(heap_rva, HeapAllocateFn)(heap, size, 0, 0);
}

/// `NativeFunctionBase::HasCallback`: whether the object carries something for
/// `Run` to call. `Impl_Invoke` asks before every call, so leaving the slot pure
/// would fault on the first native.
fn hasCallback(this: *Object) callconv(.c) bool {
    return this.callback != null;
}

/// `NativeFunctionDef::Run`. The VM calls it with the receiver cell, the
/// registry, the stack id, the result cell and the frame, and expects false
/// only when the call could not be made.
fn run(
    this: *Object,
    base: *value.VMValue,
    registry: *vm.Registry,
    stack_id: u32,
    result: *value.VMValue,
    state: *vm.VMState,
) callconv(.c) bool {
    // A `Global Native` function carries a `StaticFunctionTag` instead of an
    // instance, so there is no receiver to unpack. `registry` and `stack_id`
    // belong to the long callback signature, which this package does not build.
    _ = base;
    _ = registry;
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

    callback(&cells, count, result);
    return true;
}

/// Build one native and hand it over. Only `Global Native` functions are built:
/// the constructor is always told the function is static.
pub fn register(registry: *vm.Registry, signature: Signature, callback: Callback) !void {
    if (signature.params.len > max_params) return error.TooManyParams;

    const raw = heapAllocate(@sizeOf(Object)) orelse return error.OutOfMemory;
    const object: *Object = @ptrCast(@alignCast(raw));

    game.fnAt(ctor_rva, CtorFn)(object, signature.name, signature.class, 1, @intCast(signature.params.len));

    object.ret_type = @backingInt(signature.ret);
    // The game's parameter table ctor (RVA 0x014DCFF0) skips the allocation
    // entirely when there is nothing to hold, so a zero-parameter native has a
    // null table and nothing to patch.
    if (signature.params.len > 0) {
        const parameters = object.params.data orelse return error.NoParamTable;
        for (signature.params, 0..) |type_id, index| {
            parameters[index].type = @backingInt(type_id);
        }
    }

    const boxed: *const anyopaque = @ptrCast(callback);
    object.callback = boxed;
    object.vptr = slots();

    registry.registerFunction(object);
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
