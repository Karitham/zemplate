const std = @import("std");
const utils = @import("utils.zig");
const testing = std.testing;

/// Token represents the offset inside a file where a token exists
pub const Token = union(enum) {
    /// open_brace is the start of the opening brace in a block
    open_brace: usize,
    /// close_brace is the end_keyword of the closing brace in a block
    /// the idea behind, is that now we can slice
    /// text[open_brace..close_brace] and get the full block
    close_brace: usize,

    /// ident represents an identifier
    /// it's stored in a way that the whole identifier is
    /// text[ident.start..ident.end]
    ident: struct { start: usize, end: usize },

    /// range_keyword keyword
    range_keyword: usize,

    /// end_keyword keyword
    end_keyword: usize,
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
                    '{' => if (self.text.len > i + 1 and self.text[i + 1] == '{') Token{ .open_brace = i } else null,
                    '}' => if (self.text.len > i + 1 and self.text[i + 1] == '}') Token{ .close_brace = i + 2 } else null, // see Token.close_brace
                    '.' => switch (tokens[tokens.len - 1]) {
                        Token.open_brace, Token.range_keyword => x: {
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
                    'r' => if (tokens[tokens.len - 1] == Token.open_brace and
                        self.text.len > i + 5 and
                        std.mem.eql(u8, self.text[i .. i + 5], "range"))
                        //
                        Token{ .range_keyword = i }
                    else
                        null,

                    'e' => if (tokens[tokens.len - 1] == Token.open_brace and
                        self.text.len > i + 3 and
                        std.mem.eql(u8, self.text[i .. i + 3], "end"))
                        //
                        Token{ .end_keyword = i }
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
    /// It contains the range_keyword at which that block operates
    /// and it's possible values
    pub const Decl = union(enum) {
        /// the block is an identifier
        ident: Block,
        operation: OpBlock,
        decls: []const Decl,

        pub const OpBlock = union(enum) {
            end: Block,
            range: Block,
        };

        // alias
        const Tupl = utils.Tuple(?Decl, usize);

        /// parse a declaration
        fn parse(comptime toks: []const Token, text: []const u8) !Tupl {
            var i: usize = 0;
            switch (toks[i]) {
                Token.open_brace => {
                    i += 1;

                    return switch (toks[i]) {
                        Token.close_brace => Tupl.init(null, 2), // empty block
                        Token.ident => Decl.parse_ident(toks, text),
                        Token.range_keyword => Decl.parse_range(toks, text),
                        Token.end_keyword => Decl.parse_end(toks),
                        else => Error.expected_ident,
                    };
                },
                else => {},
            }
            return Error.expected_open_bracece;
        }

        /// parse_ident parses an identifier
        fn parse_ident(toks: []const Token, text: []const u8) !Tupl {
            if (toks.len < 3) return Error.expected_ident;
            if (toks[0] != Token.open_brace) return Error.expected_ident;
            if (toks[1] != Token.ident) return Error.expected_ident;
            if (toks[2] != Token.close_brace) return Error.expected_ident;

            var range: Block = .{
                .start = toks[0].open_brace,
                .tag = text[toks[1].ident.start..toks[1].ident.end],
                .end = toks[2].close_brace,
            };

            const i = Decl{ .ident = range };

            return Tupl.init(i, 3);
        }

        /// parse_end_keyword parses the end_keyword keyword with its braces
        fn parse_end(toks: []const Token) !Tupl {
            if (toks.len < 3) return Error.expected_end_keyword;
            if (toks[0] != Token.open_brace) return Error.expected_end_keyword;
            if (toks[1] != Token.end_keyword) return Error.expected_end_keyword;
            if (toks[2] != Token.close_brace) return Error.expected_end_keyword;

            return Tupl.init(Decl{ .operation = .{ .end = .{ .start = toks[0].open_brace, .end = toks[2].close_brace } } }, 3);
        }

        /// parse_range_keyword parses a range_keyword
        fn parse_range(comptime toks: []const Token, text: []const u8) !Tupl {
            if (toks.len < 3) return Error.expected_range_keyword;
            if (toks[0] != Token.open_brace) return Error.open_brace;
            if (toks[1] != Token.range_keyword) return Error.expected_range_keyword;
            if (toks[2] != Token.ident) return Error.expected_ident;
            if (toks[3] != Token.close_brace) return Error.expected_close_brace;

            var decls: []const Decl = ([_]Decl{
                Decl{
                    .operation = .{
                        .range = .{
                            .start = toks[0].open_brace,
                            .tag = text[toks[2].ident.start..toks[2].ident.end],
                            .end = toks[3].close_brace,
                        },
                    },
                },
            })[0..]; // I hate this, but I'm not familar enough with the syntax to do it better

            var i: usize = 4;
            comptime {
                while (i < toks.len) {
                    const d = try Decl.parse(toks[i..], text);
                    i += d.get(1);

                    if (d.get(0)) |decl| {
                        decls = decls ++ [_]Decl{decl};
                        if (Decl.operation == decl and OpBlock.end == decl.operation) break;
                    }
                }
            }

            return Tupl.init(Decl{ .decls = decls }, i);
        }
    };

    /// Block is a range_keyword of tokens
    /// It *must* have a start and end_keyword
    pub const Block = struct {
        /// tag is the identifier that the range_keyword is for
        tag: ?[]const u8 = null,

        /// start is the start of the range_keyword, text[start..end_keyword] => no more placeholders
        start: usize = undefined,

        /// end_keyword is the end_keyword of the range_keyword, text[start..end_keyword] => no more placeholders
        end: usize = undefined,
    };

    /// Errors met while parsing
    /// TODO: Find a good way to report errors such that we give file position to the user
    pub const Error = error{
        expected_close_bracece,
        expected_open_bracece,
        expected_ident,
        expected_end_keyword,
        expected_range_keyword,
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

test "parse range" {
    comptime var decls = try Parser.new("{{ range .foo }} {{ .bar }} {{ end }}").parse();
    const range_decl = decls[0];
    try testing.expectEqual(decls.len, 1);
    try utils.expect_string("expect foo", "foo", range_decl.decls[0].operation.range.tag.?);
    try testing.expectEqual(0, range_decl.decls[0].operation.range.start);
    try testing.expectEqual(16, range_decl.decls[0].operation.range.end);
    try utils.expect_string("expect bar", "bar", range_decl.decls[1].ident.tag.?);
    try testing.expectEqual(17, range_decl.decls[1].ident.start);
    try testing.expectEqual(27, range_decl.decls[1].ident.end);
    try testing.expectEqual(28, range_decl.decls[2].operation.end.start);
    try testing.expectEqual(37, range_decl.decls[2].operation.end.end);

    comptime decls = try Parser.new("{{ range .foo }} {{ .bar }} {{ end }} {{ .baz }}").parse();
    try testing.expectEqual(decls.len, 2);
    try utils.expect_string("expect foo", "foo", decls[0].decls[0].operation.range.tag.?);
    try testing.expectEqual(0, decls[0].decls[0].operation.range.start);
    try testing.expectEqual(16, decls[0].decls[0].operation.range.end);
    try utils.expect_string("expect bar", "bar", decls[0].decls[1].ident.tag.?);
    try testing.expectEqual(17, decls[0].decls[1].ident.start);
    try testing.expectEqual(27, decls[0].decls[1].ident.end);
    try testing.expectEqual(28, decls[0].decls[2].operation.end.start);
    try testing.expectEqual(37, decls[0].decls[2].operation.end.end);
    try utils.expect_string("expect baz", "baz", decls[1].ident.tag.?);
    try testing.expectEqual(38, decls[1].ident.start);
    try testing.expectEqual(48, decls[1].ident.end);

    // recursive
    comptime decls = try Parser.new("{{ range .foo }} {{ range .bar }} {{ .baz }} {{ end }} {{ end }}").parse();
    try testing.expectEqual(decls.len, 1);
    try utils.expect_string("expect foo", "foo", decls[0].decls[0].operation.range.tag.?);
    try testing.expectEqual(0, decls[0].decls[0].operation.range.start);
    try testing.expectEqual(16, decls[0].decls[0].operation.range.end);
    try utils.expect_string("expect bar", "bar", decls[0].decls[1].decls[0].operation.range.tag.?);
    try testing.expectEqual(17, decls[0].decls[1].decls[0].operation.range.start);
    try testing.expectEqual(33, decls[0].decls[1].decls[0].operation.range.end);
    try utils.expect_string("expect baz", "baz", decls[0].decls[1].decls[1].ident.tag.?);
    try testing.expectEqual(34, decls[0].decls[1].decls[1].ident.start);
    try testing.expectEqual(44, decls[0].decls[1].decls[1].ident.end);
    try testing.expectEqual(45, decls[0].decls[1].decls[2].operation.end.start);
    try testing.expectEqual(54, decls[0].decls[1].decls[2].operation.end.end);
    try testing.expectEqual(55, decls[0].decls[2].operation.end.start);
    try testing.expectEqual(64, decls[0].decls[2].operation.end.end);

    comptime decls = Parser.new("{{ range .foo }} {{ .bar }}").parse() catch |err|
        try testing.expectEqual(err, Parser.Error.expected_end_keyword);

    comptime decls = Parser.new("{{ range .foo }}").parse() catch |err|
        try testing.expectEqual(err, Parser.Error.expected_end_keyword);
}

test "parse idents" {
    comptime var decls = try Parser.new("").parse();
    try testing.expectEqual(0, decls.len);

    comptime decls = try Parser.new("{{ .foo }}").parse();
    try testing.expectEqual(1, decls.len);
    try utils.expect_string("expect foo", "foo", decls[0].ident.tag.?);
    try testing.expectEqual(0, decls[0].ident.start);
    try testing.expectEqual(10, decls[0].ident.end);

    comptime decls = try Parser.new("{{ .foo }} {{ .bar }}").parse();
    try testing.expectEqual(2, decls.len);
    try utils.expect_string("expect foo", "foo", decls[0].ident.tag.?);
    try testing.expectEqual(0, decls[0].ident.start);
    try testing.expectEqual(10, decls[0].ident.end);
    try utils.expect_string("expect bar", "bar", decls[1].ident.tag.?);
    try testing.expectEqual(11, decls[1].ident.start);
    try testing.expectEqual(21, decls[1].ident.end);
}

test "tokenize idents" {
    // none
    comptime var tokens = try Parser.new("").tokenize();
    try testing.expectEqual(tokens.len, 0);

    // basic
    comptime tokens = try Parser.new(" {{ .foo }} not inside").tokenize();
    try testing.expectEqual(tokens.len, 3);
    try testing.expectEqual(Token{ .open_brace = 1 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 5, .end = 8 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_brace = 11 }, tokens[2]);

    // nested
    comptime tokens = try Parser.new("{{ .foo.bar }}").tokenize();
    try testing.expectEqual(tokens.len, 3);
    try testing.expectEqual(Token{ .open_brace = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 11 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_brace = 14 }, tokens[2]);

    // multiple
    comptime tokens = try Parser.new("{{ .foo }} {{ .bar }}").tokenize();
    try testing.expectEqual(tokens.len, 6);
    try testing.expectEqual(Token{ .open_brace = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 4, .end = 7 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_brace = 10 }, tokens[2]);
    try testing.expectEqual(Token{ .open_brace = 11 }, tokens[3]);
    try testing.expectEqual(Token{ .ident = .{ .start = 15, .end = 18 } }, tokens[4]);
    try testing.expectEqual(Token{ .close_brace = 21 }, tokens[5]);

    // random whitespace
    comptime tokens = try Parser.new("{{  .foo         }}").tokenize();
    try testing.expectEqual(tokens.len, 3);
    try testing.expectEqual(Token{ .open_brace = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .ident = .{ .start = 5, .end = 8 } }, tokens[1]);
    try testing.expectEqual(Token{ .close_brace = 19 }, tokens[2]);
}

test "tokenize range_keyword" {
    comptime var tokens = try Parser.new("{{ range .foo }} {{ .bar }} {{ end }}").tokenize();
    try testing.expectEqual(tokens.len, 10);
    try testing.expectEqual(Token{ .open_brace = 0 }, tokens[0]);
    try testing.expectEqual(Token{ .range_keyword = 3 }, tokens[1]);
    try testing.expectEqual(Token{ .ident = .{ .start = 10, .end = 13 } }, tokens[2]);
    try testing.expectEqual(Token{ .close_brace = 16 }, tokens[3]);
    try testing.expectEqual(Token{ .open_brace = 17 }, tokens[4]);
    try testing.expectEqual(Token{ .ident = .{ .start = 21, .end = 24 } }, tokens[5]);
    try testing.expectEqual(Token{ .close_brace = 27 }, tokens[6]);
    try testing.expectEqual(Token{ .open_brace = 28 }, tokens[7]);
    try testing.expectEqual(Token{ .end_keyword = 31 }, tokens[8]);
    try testing.expectEqual(Token{ .close_brace = 37 }, tokens[9]);
}
