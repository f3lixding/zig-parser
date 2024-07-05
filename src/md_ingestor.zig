const std = @import("std");
const ArrayList = @import("std").ArrayList;

const Self = @This();

pub const ParsingError = error{
    EmptyBuffer,
    EmtpyNodeList,
    FormattingError,
};

const State = enum {
    normal,
    looking_for_list_items,
};

orig_buffer: ?[]const u8 = null,
nodes: ?ArrayList(Node) = null,
parsed_buffer: ?[]u8 = null,
idx: usize = 0,
capacity: usize = 1000,
alloc: std.mem.Allocator,

const Node = union(enum) {
    text: []const u8,
    list: ArrayList(Node),
    list_item: ArrayList(Node),
    bold: ArrayList(Node),

    pub fn to_html(self: Node, alloc: std.mem.Allocator) ![]const u8 {
        var res = ArrayList(u8).init(alloc);

        switch (self) {
            .text => |text| return text,
            .list => |children| {
                try res.appendSlice("<ul>");

                for (children.items) |child| {
                    const child_to_html = try child.to_html(alloc);
                    defer alloc.free(child_to_html);
                    try res.appendSlice(child_to_html);
                }

                try res.appendSlice("</ul>");
            },
            .list_item => |children| {
                try res.appendSlice("<li>");

                for (children.items) |child| {
                    const child_to_html = try child.to_html(alloc);
                    defer alloc.free(child_to_html);
                    try res.appendSlice(child_to_html);
                }

                try res.appendSlice("</li>");
            },
            .bold => |children| {
                try res.appendSlice("<b>");

                for (children.items) |child| {
                    const child_to_html = try child.to_html(alloc);
                    defer alloc.free(child_to_html);
                    try res.appendSlice(child_to_html);
                }

                try res.appendSlice("</b>");
            },
        }

        return res.toOwnedSlice();
    }

    pub fn deinit(self: Node) void {
        switch (self) {
            .text => |text| {
                _ = text;
                std.debug.print("Freeing text\n", .{});
            },
            .list,
            .list_item,
            .bold,
            => |nodes| {
                std.debug.print("Freeing nodes\n", .{});
                for (nodes.items) |node| {
                    node.deinit();
                }
                nodes.deinit();
            },
        }
    }
};

pub fn init_with_path(alloc: std.mem.Allocator, _: []const u8, capacity: usize) !Self {
    var array_list = ArrayList(Node).init(alloc);
    const msg = try alloc.dupe(u8, "Hello");
    array_list.append(.{ .text = msg }) catch unreachable;
    array_list.append(.{ .list = ArrayList(Node).init(alloc) }) catch unreachable;

    return .{ .alloc = alloc, .capacity = capacity, .idx = 1, .nodes = array_list };
}

pub fn init_with_buffer(alloc: std.mem.Allocator, buf: []const u8, _: usize) !Self {
    return .{ .alloc = alloc, .orig_buffer = buf };
}

pub fn deinit(self: *Self) void {
    if (self.orig_buffer) |buf|
        self.alloc.free(buf);

    if (self.nodes) |nodes| {
        for (nodes.items) |node| {
            node.deinit();
        }
        nodes.deinit();
    }
}

pub fn parse(self: *Self) !void {
    const orig_buffer = self.orig_buffer orelse return ParsingError.EmptyBuffer;
    const end_idx = orig_buffer.len;
    const asts = try self.parse_to_ast(0, end_idx);
    self.nodes = asts;
    try self.parse_to_html();
}

// Sample
// Some text here
// - a list item here
// - another list item here
// **bold text here**
// The merging of ArrayList of Nodes involves copying right now. But that's something to be optimized later
fn parse_to_ast(self: *Self, state: State, begin_idx: usize, end_idx: usize) !ArrayList(Node) {
    std.debug.print("begin_idx: {}, end_idx: {}\n", .{ begin_idx, end_idx });
    const orig_buf = self.orig_buffer orelse return ParsingError.EmptyBuffer;
    var res = ArrayList(Node).init(self.alloc);
    var idx = begin_idx;

    while (idx < end_idx) {
        switch (orig_buf[idx]) {
            '-' => {
                // list items
                if (state == .normal) {
                    var is_last_char_new_line = false;
                    const loc_end_idx = for (idx..end_idx) |i| {
                        switch (orig_buf[i]) {
                            '\n' => is_last_char_new_line = true,
                            '-' => is_last_char_new_line = false,
                            else => {
                                if (is_last_char_new_line)
                                    break i;
                            },
                        }
                    } else end_idx; // this should be the end of the list
                    const children = try self.parse_to_ast(.looking_for_list_items, idx, loc_end_idx);
                    const list = Node{
                        .list = children,
                    };
                    try res.append(list);
                    idx = loc_end_idx;
                } else {
                    // Everything between begin and end idx should be a part of a ul and every line should be a list item
                    const loc_end_idx = for (idx..end_idx) |i| {
                        if (orig_buf[i] == '\n') break i;
                    } else end_idx;
                    const children = try self.parse_to_ast(.normal, idx + 1, loc_end_idx);
                    const list_item = Node{ .list_item = children };
                    try res.append(list_item);

                    idx = loc_end_idx + 1;
                }
            },
            ' ', '\t' => {
                idx += 1;
            },
            else => {
                // Just going to assume this is a regular line of text
                const loc_end_idx = for (idx..end_idx) |i| {
                    if (orig_buf[i] == '\n') break i;
                } else end_idx;
                try res.append(Node{ .text = orig_buf[idx..loc_end_idx] });
                if (loc_end_idx < end_idx) {
                    idx = loc_end_idx + 1;
                } else {
                    break;
                }
            },
        }
    }

    return res;
}

fn parse_to_html(self: *Self) !void {
    const nodes = self.nodes orelse return ParsingError.EmtpyNodeList;
    _ = nodes;
}

test "init_test" {
    const allocator = std.testing.allocator;
    const test_buf =
        \\Sample
        \\Some text here
        \\- A list item here
        \\- Another list item here
    ;
    const test_buf_heap = try allocator.dupe(u8, test_buf);
    var ast = try Self.init_with_buffer(allocator, test_buf_heap, 10);
    defer ast.deinit();
    const res = try ast.parse_to_ast(.normal, 0, ast.orig_buffer.?.len);
    for (res.items) |node| {
        defer node.deinit();
        const html = try node.to_html(allocator);
        // defer allocator.free(html);
        std.debug.print("HTML: {s}\n", .{html});
    }
    defer res.deinit();
}

test "to_owned_slice_test" {
    const allocator = std.testing.allocator;
    const test_str = "This is a test string";
    var list = ArrayList(u8).init(allocator);
    for (0..test_str.len) |i| {
        try list.append(test_str[i]);
    }
    try list.appendSlice("\n This is another line\n");

    const owned_slice = try list.toOwnedSlice();
    defer allocator.free(owned_slice);
}
