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
        return Self{
            .text = input,
            .decls = comptime try parser.new(input).parse(),
        };
    }

    /// render renders a template
    pub fn render(comptime self: Self, writer: anytype, comptime args: anytype) !void {
        var last_off: usize = 0;

        inline for (self.decls) |d| try renderDecl(writer, args, d, &last_off, self.text);

        try writer.writeAll(self.text[last_off..]);
    }

    fn renderDecl(writer: anytype, comptime args: anytype, comptime decl: parser.Decl, last_off: *usize, text: []const u8) !void {
        switch (decl) {
            parser.Decl.ident => {
                try writer.writeAll(text[last_off.*..decl.ident.start]);

                const v = comptime try utils.getField([]const u8, args, decl.ident.tag.?);
                try writer.writeAll(v);

                last_off.* = decl.ident.end;
            },
            parser.Decl.decls => {
                switch (decl.decls[0]) {
                    parser.Decl.range => {
                        try writer.writeAll(text[last_off.*..decl.decls[0].range.start]);
                        last_off.* = decl.decls[0].range.end;

                        const args2 = @field(args, decl.decls[0].range.tag.?);

                        inline for (args2) |arg2| {
                            var new_off: usize = last_off.*;
                            inline for (decl.decls[1..]) |d| {
                                try renderDecl(writer, arg2, d, &new_off, text);
                            }
                        }

                        last_off.* = decl.decls[decl.decls.len - 1].end.end;
                    },
                    else => {},
                }
            },
            parser.Decl.end => {
                try writer.writeAll(text[last_off.*..decl.end.start]);
                last_off.* = decl.end.end;
            },
            else => {},
        }
    }
};

test "parsing" {
    _ = @import("parser.zig");
    _ = @import("utils.zig");
}

test "render range" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new("{{ range .foo }}{{ .bar }}{{ end }}");
        try t.render(out.writer(), .{ .foo = .{ &.{ .bar = "hello " }, &.{ .bar = "world" } } });
        try utils.expectString("hello world", out.items);
    }

    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new("{{ range .foo }}{{ range .baz }}{{ .bar }} {{ end }}{{ end }}");
        try t.render(out.writer(), .{ .foo = .{ &.{
            .baz = .{
                &.{ .bar = "Oh" },
                &.{ .bar = "hi" },
                &.{ .bar = "mark!" },
            },
        }, &.{ .baz = .{
            &.{ .bar = "I did not" },
            &.{ .bar = "hit her" },
            &.{ .bar = "I did nawt!" },
        } } } });
        try utils.expectString(out.items, "Oh hi mark! I did not hit her I did nawt! ");
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new(
            \\{{ range .foo }}- {{ .bar }}
            \\{{ end }}
        );
        try t.render(out.writer(), .{ .foo = .{ &.{ .bar = "a" }, &.{ .bar = "b" }, &.{ .bar = "c" } } });
        try utils.expectString(
            \\- a
            \\- b
            \\- c
            \\
        , out.items);
    }
}

test "render idents" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new("{{ .foo }}");
        try t.render(out.writer(), .{ .foo = "bar123" });
        try utils.expectString(out.items, "bar123");
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new(" {{ .foo }} {{ .bar }} {{ .foo }} ");
        try t.render(out.writer(), .{ .bar = "bar123", .foo = "foo321" });
        try utils.expectString(out.items, " foo321 bar123 foo321 ");
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new("{{ .foo }} foo between the bars {{ .foo }}");
        try t.render(out.writer(), .{ .foo = "bar123" });
        try utils.expectString(out.items, "bar123 foo between the bars bar123");
    }
    {
        defer out.clearRetainingCapacity();
        comptime var t = try Template.new("{{ .foo.bar }}");
        try t.render(out.writer(), .{ .foo = .{ .bar = "potat" } });
        try utils.expectString(out.items, "potat");
    }
}
