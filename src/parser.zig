const std = @import("std");
const utils = @import("utils.zig");
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

    /// range keyword
    range: usize,

    /// end keyword
    end: usize,
};

pub const Parser = struct {
    const Self = @This();
    tokens: []const Token = &.{},
    text: []const u8 = &.{},

    /// tokenize a file into a token stream & ref to source
    fn tokenize(comptime self: Self) ![]const Token {
        {
            var i: usize = 0;
            var tokens: []const Token = &.{};
            while (i < self.text.len) : (i += 1) {
                const tok: ?Token = switch (self.text[i]) {
                    '{' => if (self.text.len > i + 1 and self.text[i + 1] == '{') Token{ .open_bra = i } else null,
                    '}' => if (self.text.len > i + 1 and self.text[i + 1] == '}') Token{ .close_bra = i + 2 } else null, // see Token.close_bra
                    '.' => switch (tokens[tokens.len - 1]) {
                        Token.open_bra, Token.range => x: {
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
                    'r' => if (tokens[tokens.len - 1] == Token.open_bra and
                        self.text.len > i + 5 and
                        std.mem.eql(u8, self.text[i .. i + 5], "range"))
                        //
                        Token{ .range = i }
                    else
                        null,

                    'e' => if (tokens[tokens.len - 1] == Token.open_bra and
                        self.text.len > i + 3 and
                        std.mem.eql(u8, self.text[i .. i + 3], "end"))
                        //
                        Token{ .end = i }
                    else
                        null,
                    else => null,
                };

                if (tok) |t| tokens = tokens ++ [_]Token{t};
            }
            return tokens;
        }
    }

    /// Decl is an *operational* block.
    /// It contains the range at which that block operates
    /// and it's possible values
    pub const Decl = union(enum) {
        /// the block is an identifier
        ident: Range,

        // alias
        const Tupl = utils.Tuple(?Decl, usize);

        /// parse a declaration
        fn parse(toks: []const Token, text: []const u8) !Tupl {
            var i: usize = 0;
            switch (toks[i]) {
                Token.open_bra => {
                    i += 1;

                    return switch (toks[i]) {
                        Token.close_bra => Tupl.init(null, 2), // empty block
                        Token.ident => Decl.parse_ident(toks, text),
                        Token.range => Tupl.init(null, 4),
                        Token.end => Tupl.init(null, 3),
                        else => Error.expected_ident,
                    };
                },
                else => {},
            }
            return Error.expected_open_brace;
        }

        /// parse_ident parses an identifier
        fn parse_ident(toks: []const Token, text: []const u8) !Tupl {
            if (toks.len < 3) return Error.expected_ident;
            if (toks[0] != Token.open_bra) return Error.expected_ident;
            if (toks[1] != Token.ident) return Error.expected_ident;
            if (toks[2] != Token.close_bra) return Error.expected_ident;

            var range: Range = .{
                .start = toks[0].open_bra,
                .tag = text[toks[1].ident.start..toks[1].ident.end],
                .end = toks[2].close_bra,
            };

            const i = Decl{ .ident = range };

            return Tupl.init(i, 3);
        }
    };

    /// Range is a range of tokens
    pub const Range = struct {
        /// tag is the identifier that the range is for
        tag: ?[]const u8 = null,

        /// start is the start of the range, text[start..end] => no more placeholders
        start: ?usize = null,

        /// end is the end of the range, text[start..end] => no more placeholders
        end: ?usize = null,
    };

    /// Errors met while parsing
    /// TODO: Find a good way to report errors such that we give file position to the user
    pub const Error = error{
        expected_close_brace,
        expected_open_brace,
        expected_ident,
        unknown,
    };

    /// new initializes a new template parser
    pub fn new(comptime input: []const u8) *Self {
        var self = Self{};
        self.text = input;
        return &self;
    }

    /// parse the file to a list of decls
    pub fn parse(comptime self: *Self) ![]const Decl {
        self.tokens = try self.tokenize();
        var decls: []const Decl = &.{};

        comptime {
            var i = 0;
            while (i < self.tokens.len) {
                const tupl = try Decl.parse(self.tokens[i..], self.text);
                if (tupl.get(0)) |d| decls = decls ++ [_]Decl{d};

                i += tupl.get(1);
            }
        }
        return decls;
    }
};

test "parse idents" {
    comptime var decls = try Parser.new("").parse();
    try testing.expectEqual(decls.len, 0);

    comptime decls = try Parser.new("{{ .foo }}").parse();
    try testing.expectEqual(decls.len, 1);
    try utils.expect_string("expect foo", decls[0].ident.tag.?, "foo");
    try testing.expectEqual(decls[0].ident.start.?, 0);
    try testing.expectEqual(decls[0].ident.end.?, 10);

    comptime decls = try Parser.new("{{ .foo }} {{ .bar }}").parse();
    try testing.expectEqual(decls.len, 2);
    try utils.expect_string("expect foo", decls[0].ident.tag.?, "foo");
    try testing.expectEqual(decls[0].ident.start.?, 0);
    try testing.expectEqual(decls[0].ident.end.?, 10);
    try utils.expect_string("expect bar", decls[1].ident.tag.?, "bar");
    try testing.expectEqual(decls[1].ident.start.?, 11);
    try testing.expectEqual(decls[1].ident.end.?, 21);
}

test "tokenize idents" {
    // none
    comptime var tokens = try Parser.new("").tokenize();
    try testing.expectEqual(tokens.len, 0);

    // basic
    comptime tokens = try Parser.new(" {{ .foo }} not inside").tokenize();
    try testing.expectEqual(tokens.len, 3);
    try testing.expectEqual(Token{ .open_bra = 1 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 5, .end = 8 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 11 }, tokens[2]);

    // nested
    comptime tokens = try Parser.new("{{ .foo.bar }}").tokenize();
    try testing.expectEqual(tokens.len, 3);
    try testing.expectEqual(Token{ .open_bra = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 11 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 14 }, tokens[2]);

    // multiple
    comptime tokens = try Parser.new("{{ .foo }} {{ .bar }}").tokenize();
    try testing.expectEqual(tokens.len, 6);
    try testing.expectEqual(Token{ .open_bra = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 7 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 10 }, tokens[2]);
    try testing.expectEqual(Token{ .open_bra = 11 }, tokens[3]);
    try testing.expectEqual(Token{ .ident = .{ .start = 15, .end = 18 } }, tokens[4]);
    try testing.expectEqual(Token{ .close_bra = 21 }, tokens[5]);

    // random whitespace
    comptime tokens = try Parser.new("{{  .foo         }}").tokenize();
    try testing.expectEqual(tokens.len, 3);
    try testing.expectEqual(Token{ .open_bra = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 5, .end = 8 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_bra = 19 }, tokens[2]);
}

test "tokenize range" {
    comptime var tokens = try Parser.new("{{ range .foo }} {{ .bar }} {{ end }}").tokenize();
    try testing.expectEqual(tokens.len, 10);
    try testing.expectEqual(Token{ .open_bra = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .range = 3 }, tokens[1]);
    try testing.expectEqual(Token{ .ident = .{ .start = 10, .end = 13 } }, tokens[2]);
    try testing.expectEqual(Token{ .close_bra = 16 }, tokens[3]);
    try testing.expectEqual(Token{ .open_bra = 17 }, tokens[4]);
    try testing.expectEqual(Token{ .ident = .{ .start = 21, .end = 24 } }, tokens[5]);
    try testing.expectEqual(Token{ .close_bra = 27 }, tokens[6]);
    try testing.expectEqual(Token{ .open_bra = 28 }, tokens[7]);
    try testing.expectEqual(Token{ .end = 31 }, tokens[8]);
    try testing.expectEqual(Token{ .close_bra = 37 }, tokens[9]);
}
