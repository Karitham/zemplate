const std = @import("std");
const parser = @import("parser.zig").Parser;
const utils = @import("utils.zig");
const testing = std.testing;

/// Template represents a template
/// It's a list of tokens and the source template
pub const Template = struct {
    const Self = @This();

    decls: []const parser.Decl = &.{},
    text: []const u8 = &.{},

    pub fn new(comptime input: []const u8) !Self {
        var self = Self{};
        self.text = input;
        comptime {
            self.decls = try parser.new(input).parse();
        }
        return self;
    }

    /// render renders a template
    pub fn render(comptime self: *Self, writer: anytype, comptime args: anytype) !void {
        var last_off: usize = 0;

        var i: usize = 0;
        while (i < self.decls.len) : (i += 1) {
            try render_decl(writer, args, self.decls[i], &last_off, self.text);
        }

        try writer.writeAll(self.text[last_off..]);
    }

    fn render_decl(writer: anytype, comptime args: anytype, decl: parser.Decl, last_off: *usize, text: []const u8) !void {
        const t = @typeInfo(@TypeOf(args));
        if (t != .Struct) @compileError("args must be a struct or union");

        switch (decl) {
            parser.Decl.ident => {
                const ident = decl.ident;

                try writer.writeAll(text[last_off.*..decl.start_or(text.len)]);
                inline for (t.Struct.fields) |f| {
                    if (std.mem.eql(u8, f.name, ident.tag.?)) {
                        try writer.writeAll(@field(args, f.name));
                        break;
                    }
                }
                last_off.* = ident.end;

                try writer.writeAll(text[last_off.*..decl.end_or(text.len)]);
            },
            else => {
                _ = text;
            },
        }
    }
};

test "parsing" {
    _ = @import("parser.zig");
}

test "render range" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    comptime var t = try Template.new("{{range .foo }}{{ .bar }}{{end}}");
    try testing.expectEqual(1, t.decls.len);
    try utils.expect_string("expect foo", "foo", t.decls[0].decls[0].range.tag.?);
    try testing.expectEqual(0, t.decls[0].decls[0].range.start);
    try testing.expectEqual(15, t.decls[0].decls[0].range.end);

    try utils.expect_string("expect bar", "bar", t.decls[0].decls[1].ident.tag.?);
    try testing.expectEqual(15, t.decls[0].decls[1].ident.start);
    try testing.expectEqual(25, t.decls[0].decls[1].ident.end);

    try testing.expect(null == t.decls[0].decls[2].end.tag);
    try testing.expectEqual(25, t.decls[0].decls[2].end.start);
    try testing.expectEqual(32, t.decls[0].decls[2].end.end);

    // try t.render(out.writer(), .{ .foo = &.{ .{ .bar = "hello " }, .{ .bar = "world" } } });
    // try utils.expect_string("render range", "hello world", out.items);
}

test "render idents" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new("{{ .foo }}");
        try t.render(out.writer(), .{ .foo = "bar123" });
        try utils.expect_string("single ident replace", "bar123", out.items);
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new(" {{ .foo }} {{ .bar }} {{ .foo }} ");
        try t.render(out.writer(), .{ .bar = "bar123" });
        try utils.expect_string(
            "multiple ident replace with leading and trailing whitespace",
            "  bar123  ",
            out.items,
        );
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new("{{ .foo }} foo between the bars {{ .foo }}");
        try t.render(out.writer(), .{ .foo = "bar123" });
        try utils.expect_string(
            "single ident with other text appearing multiple times",
            "bar123 foo between the bars bar123",
            out.items,
        );
    }
}
