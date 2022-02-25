const std = @import("std");
const parser = @import("parser.zig").Parser;
const utils = @import("utils.zig");
const testing = std.testing;

/// Template represents a template
/// It's a list of tokens and the source template
pub const Template = struct {
    const Self = @This();

    blocks: []const parser.Decl = &.{},
    text: []const u8 = &.{},

    pub fn new(comptime input: []const u8) !Self {
        var self = Self{};
        self.text = input;
        self.blocks = try parser.new(input).parse();
        return self;
    }
    /// render renders a template
    pub fn render(comptime self: *Self, writer: anytype, comptime args: anytype) !void {
        const t = @typeInfo(@TypeOf(args));
        if (t != .Struct) @compileError("args must be a struct or union");

        var last_off: usize = 0;
        // basic ident replacement
        inline for (self.blocks) |ins| {
            switch (ins) {
                parser.Decl.ident => {
                    const ident = ins.ident;

                    try writer.writeAll(self.text[last_off..ident.start.?]);
                    last_off = ident.end.?;
                    inline for (t.Struct.fields) |f| {
                        if (std.mem.eql(u8, f.name, ident.tag.?)) {
                            try writer.writeAll(@field(args, f.name));
                        }
                    }
                },
            }
        }
        try writer.writeAll(self.text[last_off..self.text.len]);
    }
};

test "parsing" {
    _ = @import("parser.zig");
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
        comptime var t = try Template.new(" {{ .foo }} {{ .bar }} ");
        try t.render(out.writer(), .{ .foo = "bar123" });
        try utils.expect_string(
            "multiple ident replace with leading and trailing whitespace",
            " bar123  ",
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
