//! BSScript::VMValue: the 16 byte cell every Papyrus value travels in.

const std = @import("std");
const game = @import("game.zig");

/// `VMValue::type` ids. Non-exhaustive: a script object's id is a type pointer.
pub const Type = enum(u64) {
    none = 0,
    identifier = 1,
    identifier_array = 11,
    string = 2,
    int = 3,
    float = 4,
    boolean = 5,
    string_array = 12,
    int_array = 13,
    float_array = 14,
    boolean_array = 15,
    _,
};

/// Array id = raw id + 10.
pub fn arrayOf(t: Type) Type {
    return @enumFromInt(@intFromEnum(t) + 10);
}

/// `BSScript::TypeInfo`, 8 bytes: raw id below 0x10, else `ObjectTypeInfo*` (bit 0 = array of it).
pub const TypeInfo = extern struct {
    raw: u64,
};

/// `BSScript::Array`: 0x20 header, element `VMValue`s inline at +0x20 + i*0x10.
/// Fresh from `createArray`: `ref_count` 2 (creator + VM tracking list).
pub const Array = extern struct {
    ref_count: u32,
    _pad04: [4]u8,
    element_type: u64,
    size: u32,
    _pad14: [4]u8,
    _unk18: [8]u8,

    pub fn elements(self: *Array) [*]VMValue {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Array));
    }
};

pub const Data = extern union {
    int: i32,
    uint: u32,
    float: f32,
    boolean: bool,
    pointer: ?*anyopaque,
    string: ?[*:0]const u8,
    /// Whole payload; `none` clears it.
    raw: u64,
};

pub const VMValue = extern struct {
    type: Type = .none,
    data: Data = .{ .raw = 0 },

    /// `SetInt` without `Destroy`; the result cell arrives as `none`.
    pub fn setInt(self: *VMValue, v: i32) void {
        self.type = .int;
        self.data.int = v;
    }

    pub fn setFloat(self: *VMValue, v: f32) void {
        self.type = .float;
        self.data.float = v;
    }

    pub fn setBool(self: *VMValue, v: bool) void {
        self.type = .boolean;
        self.data.boolean = v;
    }

    pub fn setNone(self: *VMValue) void {
        self.type = .none;
        self.data = .{ .raw = 0 };
    }
};

const AssignFn = *const fn (*VMValue, *const VMValue) callconv(.c) void;
const ResetFn = *const fn (*VMValue) callconv(.c) void;

/// `Variable::assign` (id 104297, RVA `0x01491B00`): release `target`'s payload,
/// take a reference to `value`'s. Required for refcounted payloads (string, object, array).
pub fn assign(target: *VMValue, value: *const VMValue) void {
    game.fnAt(0x01491B00, AssignFn)(target, value);
}

/// `Variable::reset` (id 104296, RVA `0x01491A00`): release `target`'s payload.
pub fn reset(target: *VMValue) void {
    game.fnAt(0x01491A00, ResetFn)(target);
}

test "VMValue is the header's 16 bytes" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(VMValue));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(VMValue, "type"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(VMValue, "data"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Data));
}

test "VMValue type ids keep PapyrusValue.h's values" {
    try std.testing.expectEqual(@as(u64, 0), @backingInt(Type.none));
    try std.testing.expectEqual(@as(u64, 2), @backingInt(Type.string));
    try std.testing.expectEqual(@as(u64, 3), @backingInt(Type.int));
    try std.testing.expectEqual(@as(u64, 4), @backingInt(Type.float));
    try std.testing.expectEqual(@as(u64, 5), @backingInt(Type.boolean));
    try std.testing.expectEqual(@as(u64, 15), @backingInt(Type.boolean_array));
}

test "array ids encode raw id + 10 and the Array header is 0x20" {
    try std.testing.expectEqual(@as(u64, 11), @backingInt(Type.identifier_array));
    try std.testing.expectEqual(Type.string_array, arrayOf(.string));
    try std.testing.expectEqual(Type.int_array, arrayOf(.int));
    try std.testing.expectEqual(Type.boolean_array, arrayOf(.boolean));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(TypeInfo));
    try std.testing.expectEqual(@as(usize, 0x20), @sizeOf(Array));
    try std.testing.expectEqual(@as(usize, 0x00), @offsetOf(Array, "ref_count"));
    try std.testing.expectEqual(@as(usize, 0x08), @offsetOf(Array, "element_type"));
    try std.testing.expectEqual(@as(usize, 0x10), @offsetOf(Array, "size"));
}

test "a written value reads back" {
    var v: VMValue = .{};
    v.setInt(-7);
    try std.testing.expectEqual(Type.int, v.type);
    try std.testing.expectEqual(@as(i32, -7), v.data.int);

    v.setFloat(0.5);
    try std.testing.expectEqual(Type.float, v.type);
    try std.testing.expectEqual(@as(f32, 0.5), v.data.float);

    v.setBool(true);
    try std.testing.expectEqual(Type.boolean, v.type);
    try std.testing.expect(v.data.boolean);

    v.setNone();
    try std.testing.expectEqual(Type.none, v.type);
    try std.testing.expectEqual(@as(u64, 0), v.data.raw);
}
