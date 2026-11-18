//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
pub const plugin_api = @import("plugin_api.zig");

// Pull in the tests of every re-exported declaration. Without this,
// `pub const plugin_api` is lazily analyzed and its tests never run:
// `zig build test` reports 1/1 instead of 4/4.
test {
    std.testing.refAllDecls(@This());
}
