//! BSScript::VMValue: the 16 byte cell every Papyrus value travels in.

const std = @import("std");

/// `VMValue::type`, and the ids a native declares its parameters and return
/// with. Non exhaustive, because a script object's id is a type pointer.
pub const Type = enum(u64) {
    none = 0,
    identifier = 1,
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

pub const Data = extern union {
    int: i32,
    uint: u32,
    float: f32,
    boolean: bool,
    pointer: ?*anyopaque,
    string: ?[*:0]const u8,
    /// The whole payload at once, which is how `none` clears it: a `VMValue`
    /// is a `u64` type tag over eight value bytes.
    raw: u64,
};

pub const VMValue = extern struct {
    type: Type = .none,
    data: Data = .{ .raw = 0 },

    /// The game's `SetInt` without its `Destroy` call. A native's result cell
    /// arrives as a zeroed `none`, so there is nothing to release first.
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
