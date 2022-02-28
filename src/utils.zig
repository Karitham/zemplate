const std = @import("std");
const testing = std.testing;

/// is a helper function for testing
pub fn expectString(expected: []const u8, actual: []const u8) !void {
    testing.expect(std.mem.eql(u8, expected, actual)) catch |err| {
        std.log.err("expected: \'{s}\', got: \'{s}\'", .{ expected, actual });
        return err;
    };
}

/// Tuple is 2 valued tuple
/// Stolen from <https://gist.github.com/adrusi/54ed2be2fbc6e9fb0c68f3c6f8706f9b>
pub fn Tuple(comptime T0: type, comptime T1: type) type {
    return struct {
        const types = [_]type{ T0, T1 };

        @"0": T0,
        @"1": T1,

        pub fn init(x0: T0, x1: T1) @This() {
            return .{ .@"0" = x0, .@"1" = x1 };
        }

        pub fn unpack(self: @This(), vars: type) void {
            if (comptime @typeInfo(@TypeOf(vars[0])) != .Null) vars[0].* = self.@"0";
            if (comptime @typeInfo(@TypeOf(vars[1])) != .Null) vars[1].* = self.@"1";
        }

        pub fn set(self: *@This(), comptime index: usize, value: anytype) void {
            comptime {
                if (@TypeOf(value) != types[index]) {
                    @compileLog("Invalid type for index" ++ index ++ ":" ++ @typeName(@TypeOf(value)));
                }
            }
            switch (comptime index) {
                0 => self.@"0" = value,
                1 => self.@"1" = value,
                else => @compileLog("Invalid index for Tuple: {}", index),
            }
        }

        pub fn get(self: *const @This(), comptime index: usize) switch (index) {
            0 => T0,
            1 => T1,
            else => @compileLog("Invalid index for Tuple: {}", index),
        } {
            return switch (comptime index) {
                0 => self.@"0",
                1 => self.@"1",
                else => undefined,
            };
        }
    };
}

const FieldError = error{
    FieldNotFound,
};

/// returns a field with the specified name
pub fn getField(comptime T: type, comptime args: anytype, name: []const u8) !T {
    for (name) |c, i| if (c == '.') return getField(T, @field(args, name[0..i]), name[i + 1 ..]);
    return @field(args, name);
}

test "parse tag" {
    var t = comptime try getField([]const u8, .{ .foo = "bar" }, "foo");
    try testing.expectEqual(t, "bar");

    t = comptime try getField([]const u8, .{ .foo = .{ .bar = "baz" } }, "foo.bar");
    try testing.expectEqual(t, "baz");

    var t2 = comptime try getField([]const []const u8, .{ .foo = &.{ "bar", "baz" } }, "foo");
    try testing.expectEqualSlices([]const u8, t2, &.{ "bar", "baz" });
}
