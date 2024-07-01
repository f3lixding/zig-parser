const std = @import("std");
const ArrayList = @import("std").ArrayList;

const Self = @This();

orig_buffer: ?[]const u8 = null,
nodes: ?ArrayList(Node) = null,
idx: usize = 0,
capacity: usize = 1000,
alloc: std.mem.Allocator,

const Node = union(enum) {
    text: []const u8,
    list: ArrayList(Node),
    paragraph: ArrayList(Node),
    body: ArrayList(Node),

    pub fn free(self: Node, alloc: std.mem.Allocator) void {
        switch (self) {
            .text => |text| {
                std.debug.print("Freeing text {s}\n", .{text});
                alloc.free(text);
            },
            .list,
            .paragraph,
            .body,
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

pub fn init_with_buffer(alloc: std.mem.Allocator, _: []const u8, _: usize) !Self {
    return .{ .alloc = alloc };
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

test "init_test" {
    const ast = Self.init_with_path(std.testing.allocator, "test.md", 10) catch unreachable;
    // _ = ast;
    defer ast.deinit();
}
