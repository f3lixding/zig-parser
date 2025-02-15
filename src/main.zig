const std = @import("std");
const config_ingestor = @import("config_ingestor.zig");
const md_ingestor = @import("md_ingestor.zig");

pub fn main() !void {
    var ci = try config_ingestor.init(std.heap.page_allocator);
    defer ci.deinit();
    const path = ci.getToReadPath().?; // we have to have a path otherwise there is no need to keep going
    std.debug.print("Path received {s}\n", .{path});

    var md = try md_ingestor.initWithPath(std.heap.page_allocator, path, 100000);
    defer md.deinit();
    try md.parse();
}
