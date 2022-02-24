const std = @import("std");
const testing = std.testing;

/// Token represents the offset inside a file where a token exists
pub const Token = union(enum) {
    /// open_bra is the start of the opening brace in a block
    open_bra: usize,
    /// close_bra is the end of the closing brace in a block
    /// the idea behind, is that now we can slice
    /// text[open_bra..close_bra] and get the full block
    close_bra: usize,

    /// ident represents an identifier
    /// it's stored in a way that the whole identifier is
    /// text[ident.start..ident.end]
    ident: struct { start: usize, end: usize },
};

/// Template represents a template
/// It's a list of tokens and the source template
pub const Template = struct {
    const Self = @This();

    tokens: []const Token = undefined,
    text: []const u8 = undefined,

    /// tokenize a file into a token stream & ref to source
    pub fn parse(comptime input: []const u8) !Self {
        var self = Self{};
        self.tokens = &.{};
        self.text = input;

        comptime {
            var i: usize = 0;
            while (i < self.text.len) : (i += 1) {
                const tok: ?Token = switch (self.text[i]) {
                    '{' => if (self.text.len > i + 1 and self.text[i + 1] == '{') Token{ .open_bra = i } else null,
                    '}' => if (self.text.len > i + 1 and self.text[i + 1] == '}') Token{ .close_bra = i + 2 } else null, // see Token.close_bra
                    '.' => switch (self.tokens[self.tokens.len - 1]) {
                        Token.open_bra => x: {
                            i += 1; // skip the dot

                            while (i < self.text.len and self.text[i] == ' ') : (i += 1) {} // eat whitespace

                            const ident_start = i;
                            while (i < self.text.len and
                                self.text[i] != '}' and
                                self.text[i] != ' ') : (i += 1)
                            {} // eat until closing brace

                            break :x if (ident_start == i) null else Token{ .ident = .{ .start = ident_start, .end = i } };
                        },
                        else => null,
                    },
                    else => null,
                };

                if (tok) |t| self.tokens = self.tokens ++ [_]Token{t};
            }
        }
        return self;
    }

    const PositionalTok = struct {
        tag: ?[]const u8 = null,
        start: ?usize = null,
        end: ?usize = null,
    };

    fn parse_positional_tok(comptime self: *Self) ![]const PositionalTok {
        comptime var to_insert: []const PositionalTok = &.{};
        comptime {
            var next_insert: PositionalTok = .{};
            for (self.tokens) |tok| {
                switch (tok) {
                    Token.open_bra => next_insert.start = tok.open_bra,
                    Token.close_bra => next_insert.end = tok.close_bra,
                    Token.ident => next_insert.tag = self.text[tok.ident.start..tok.ident.end],
                }

                if (next_insert.start != null and next_insert.end != null and next_insert.tag != null) {
                    to_insert = to_insert ++ [_]PositionalTok{next_insert};
                    next_insert = .{};
                }
            }
        }

        return to_insert;
    }

    /// render renders a template
    pub fn render(comptime self: *Self, writer: anytype, comptime args: anytype) !void {
        const t = @typeInfo(@TypeOf(args));
        if (t != .Struct) @compileError("args must be a struct or union");
        comptime var to_insert = try self.parse_positional_tok();

        var last_off: usize = 0;
        // basic ident replacement
        inline for (to_insert) |ins| {
            try writer.writeAll(self.text[last_off..ins.start.?]);
            last_off = ins.end.?;

            inline for (t.Struct.fields) |f| {
                if (std.mem.eql(u8, f.name, ins.tag.?)) {
                    try writer.writeAll(@field(args, f.name));
                }
            }
        }
        try writer.writeAll(self.text[last_off..self.text.len]);
    }
};

test "render" {
    // output
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    // values
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.parse("{{ .foo }}");
        try t.render(out.writer(), .{ .foo = "bar123" });

        try expect_string("single ident replace", "bar123", out.items);
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.parse(" {{ .foo }} {{ .bar }} ");

        try t.render(out.writer(), .{ .foo = "bar123" });

        try expect_string("multiple ident replace with leading and trailing whitespace", " bar123  ", out.items);
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.parse("{{ .foo }} foo between the bars {{ .foo }}");
        try t.render(out.writer(), .{ .foo = "bar123" });

        try expect_string(
            "single ident with other text appearing multiple times",
            "bar123 foo between the bars bar123",
            out.items,
        );
    }
}

test "parse idents" {

    // none
    comptime var t1 = try Template.parse("");
    try testing.expect(t1.tokens.len == 0);

    // basic
    comptime var t2 = try Template.parse(" {{ .foo }} not inside");
    try testing.expect(t2.tokens.len == 3);
    try testing.expectEqual(Token{ .open_bra = 1 }, t2.tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 5, .end = 8 } }, t2.tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 11 }, t2.tokens[2]);

    // nested
    comptime var t3 = try Template.parse("{{ .foo.bar }}");
    try testing.expect(t3.tokens.len == 3);
    try testing.expectEqual(Token{ .open_bra = 0 }, t3.tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 11 } }, t3.tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 14 }, t3.tokens[2]);

    // multiple
    comptime var t4 = try Template.parse("{{ .foo }} {{ .bar }}");
    try testing.expect(t4.tokens.len == 6);
    try testing.expectEqual(Token{ .open_bra = 0 }, t4.tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 7 } }, t4.tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 10 }, t4.tokens[2]);
    try testing.expectEqual(Token{ .open_bra = 11 }, t4.tokens[3]);
    try testing.expectEqual(Token{ .ident = .{ .start = 15, .end = 18 } }, t4.tokens[4]);
    try testing.expectEqual(Token{ .close_bra = 21 }, t4.tokens[5]);
}

/// expect_string is a helper function for testing
fn expect_string(name: ?[]const u8, expected: []const u8, actual: []const u8) !void {
    testing.expect(std.mem.eql(u8, expected, actual)) catch |err| {
        std.log.err("{s}: expected: \'{s}\', got: \'{s}\'", .{ name, expected, actual });
        return err;
    };
}
