const std = @import("std");
const testing = std.testing;

/// expect_string is a helper function for testing
pub fn expect_string(name: ?[]const u8, expected: []const u8, actual: []const u8) !void {
    testing.expect(std.mem.eql(u8, expected, actual)) catch |err| {
        std.log.err("{s}: expected: \'{s}\', got: \'{s}\'", .{ name, expected, actual });
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

        pub fn set(self: *@This(), comptime index: usize, value: type) void {
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
