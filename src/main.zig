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

    alloc: std.mem.Allocator,
    /// init initializes a template
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{ .alloc = alloc };
    }

    /// parse a file into a token stream & ref to source
    pub fn parse(comptime self: *Self, comptime input: []const u8) !void {
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
    }

    /// render renders a template
    pub fn render(self: *Self, writer: anytype, args: std.StringHashMap([][]const u8)) !void {
        const insert_in = struct {
            tag: ?[]const u8 = undefined,
            start: ?usize = undefined,
            end: ?usize = undefined,
        };

        var to_insert = std.ArrayList(insert_in).init(self.alloc);
        defer to_insert.deinit();

        var next_insert: insert_in = .{};
        for (self.tokens) |tok| {
            switch (tok) {
                Token.open_bra => next_insert.start = tok.open_bra,
                Token.close_bra => next_insert.end = tok.close_bra,
                Token.ident => next_insert.tag = self.text[tok.ident.start..tok.ident.end],
            }

            if (next_insert.start != null and next_insert.end != null and next_insert.tag != null) {
                try to_insert.append(next_insert);
                next_insert = .{};
            }
        }

        var last_off: usize = 0;
        // basic ident replacement
        for (to_insert.items) |ins| {
            try writer.writeAll(self.text[last_off..ins.start.?]);
            last_off = ins.end.?;

            if (args.get(ins.tag.?)) |val| {
                if (val.len > 0) try writer.writeAll(val[0][0..val[0].len]);
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
    var in = std.StringHashMap([][]const u8).init(std.testing.allocator);
    defer in.deinit();

    var bar = "bar123";
    try in.put("foo", &.{bar[0..]});

    {
        comptime var t = Template.init(std.testing.allocator);

        defer out.clearRetainingCapacity();
        try t.parse("{{ .foo }}");
        try t.render(out.writer(), in);

        try expect_string("single ident replace", "bar123", out.items);
    }
    {
        comptime var t = Template.init(std.testing.allocator);

        defer out.clearRetainingCapacity();
        try t.parse(" {{ .foo }} {{ .bar }} ");
        try t.render(out.writer(), in);

        try expect_string("multiple ident replace with leading and trailing whitespace", " bar123  ", out.items);
    }
    {
        comptime var t = Template.init(std.testing.allocator);

        defer out.clearRetainingCapacity();
        try t.parse("{{ .foo }} foo between the bars {{ .foo }}");
        try t.render(out.writer(), in);

        try expect_string(
            "single ident with other text appearing multiple times",
            "bar123 foo between the bars bar123",
            out.items,
        );
    }
}

test "parse idents" {
    comptime var t = Template.init(std.testing.allocator);

    // none
    try t.parse("");
    try testing.expect(t.tokens.len == 0);

    // basic
    try t.parse(" {{ .foo }} not inside");
    try testing.expect(t.tokens.len == 3);

    try testing.expectEqual(Token{ .open_bra = 1 }, t.tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 5, .end = 8 } }, t.tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 11 }, t.tokens[2]);

    // nested
    try t.parse("{{ .foo.bar }}");
    try testing.expect(t.tokens.len == 3);
    try testing.expectEqual(Token{ .open_bra = 0 }, t.tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 11 } }, t.tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 14 }, t.tokens[2]);

    // multiple
    try t.parse("{{ .foo }} {{ .bar }}");
    try testing.expect(t.tokens.len == 6);
    try testing.expectEqual(Token{ .open_bra = 0 }, t.tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 7 } }, t.tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 10 }, t.tokens[2]);
    try testing.expectEqual(Token{ .open_bra = 11 }, t.tokens[3]);
    try testing.expectEqual(Token{ .ident = .{ .start = 15, .end = 18 } }, t.tokens[4]);
    try testing.expectEqual(Token{ .close_bra = 21 }, t.tokens[5]);
}

/// expect_string is a helper function for testing
fn expect_string(name: ?[]const u8, expected: []const u8, actual: []const u8) !void {
    testing.expect(std.mem.eql(u8, expected, actual)) catch |err| {
        std.log.err("{s}: expected: \'{s}\', got: \'{s}\'", .{ name, expected, actual });
        return err;
    };
}
