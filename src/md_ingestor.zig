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

    pub fn free(self: Node, alloc: std.mem.Allocator) void {
        switch (self) {
            .text => |text| {
                std.debug.print("Freeing text {s}\n", .{text});
                alloc.free(text);
            },
            .list,
            .list_item,
            .bold,
            => |nodes| {
                for (nodes.items) |node| {
                    std.debug.print("Freeing node {any}\n", .{node});
                    node.free(alloc);
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

pub fn deinit(self: Self) void {
    if (self.orig_buffer) |buf|
        self.alloc.free(buf);

    if (self.nodes) |nodes| {
        for (nodes.items, 0..) |node, i| {
            if (i >= self.idx)
                break;
            std.debug.print("Freeing node {any}\n", .{node});
            node.free(self.alloc);
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
                    const children = try self.parse_to_ast(.looking_for_list_items, idx + 1, loc_end_idx);
                    defer children.deinit();
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
                    const children = try self.parse_to_ast(.normal, idx, loc_end_idx);
                    defer children.deinit();
                    for (children.items) |child|
                        try res.append(child);

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
                std.debug.print("buffer: {s}\n", .{orig_buf[idx..loc_end_idx]});
                try res.append(Node{ .text = orig_buf[begin_idx..end_idx] });
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

fn parse_to_html(_: *Self) !void {}

test "init_test" {
    const test_buf_stack =
        \\Sample
        \\Some text here
        \\- A list item here
    ;
    const test_buf = try std.testing.allocator.dupe(u8, test_buf_stack);
    var ast = try Self.init_with_buffer(std.testing.allocator, test_buf, 10);
    defer ast.deinit();
    const res = try ast.parse_to_ast(.normal, 0, ast.orig_buffer.?.len);
    defer res.deinit();
    std.debug.print("{any}\n", .{res});
}
