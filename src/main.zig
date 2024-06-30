const std = @import("std");
const config_ingestor = @import("config_ingestor.zig");

pub fn main() !void {
    var ci = try config_ingestor.init(std.heap.page_allocator);
    defer ci.deinit();
    // std.debug.print("{s}\n", .{ci.getToReadPath()});
}

test "init test" {
    const ci = try config_ingestor.init(std.heap.page_allocator);
    _ = ci;
    // defer ci.deinit();
}
