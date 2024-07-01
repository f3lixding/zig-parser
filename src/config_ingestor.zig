const std = @import("std");

const Self = @This();

const ArgType = enum {
    to_read_path,
};

const ArgOption = struct {
    opt_str: [2][]const u8,
};

const ArgTaggedUnion = union(ArgType) {
    to_read_path: ArgOption,

    fn getOptStrs(self: ArgTaggedUnion) [2][]const u8 {
        switch (self) {
            .to_read_path => |opt| {
                return opt.opt_str;
            },
        }
    }
};

const ArgValueTaggedUnion = union(ArgType) {
    to_read_path: []const u8,
};

const ScanState = union(enum) {
    fresh: void,
    looking_for_value: ArgType,
};

const opts = [_]ArgTaggedUnion{
    .{ .to_read_path = .{ .opt_str = .{ "-p", "--path" } } },
};

allocator: std.mem.Allocator,
to_read_path: ?[]const u8 = null,

pub fn init(allocator: std.mem.Allocator) !Self {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var state = ScanState{ .fresh = {} };
    var self: Self = .{ .allocator = allocator };

    for (args[1..]) |arg| {
        switch (state) {
            .fresh => {
                var idx: usize = 0;
                const end = while (idx < arg.len) : (idx += 1) {
                    if (arg[idx] == '=')
                        break idx;
                } else arg.len;

                if (end < arg.len) {
                    // this would mean we have received something in the form of "key=value"
                    const key = arg[0..end];
                    const value = arg[end + 1 ..];
                    const arg_value = getArgValueTaggedUnion(key, value).?;

                    switch (arg_value) {
                        .to_read_path => |val| {
                            // copy value from args and store it
                            const dst = try self.allocator.dupe(u8, val);
                            self.to_read_path = dst;
                        },
                    }
                } else {
                    // this would mean we have recieved something in the form of "-k" or "--key"
                    const arg_type = getArgTypeFromInput(arg).?;
                    switch (arg_type) {
                        .to_read_path => {
                            state = ScanState{ .looking_for_value = arg_type };
                        },
                    }
                }
            },
            .looking_for_value => |arg_type| {
                switch (arg_type) {
                    .to_read_path => {
                        const dst = try self.allocator.dupe(u8, arg);
                        self.to_read_path = dst;
                        state = .fresh;
                    },
                }
            },
        }
    }

    return self;
}

fn getArgValueTaggedUnion(read_opt_str: []const u8, val: []const u8) ?ArgValueTaggedUnion {
    return outer: for (opts) |opt| {
        const opt_strs = opt.getOptStrs();
        for (opt_strs) |opt_str| {
            if (std.mem.eql(u8, opt_str, read_opt_str)) {
                switch (opt) {
                    .to_read_path => {
                        const res = ArgValueTaggedUnion{ .to_read_path = val };
                        break :outer res;
                    },
                }
            }
        }
    } else null;
}

fn getArgTypeFromInput(input: []const u8) ?ArgType {
    return outer: for (opts) |opt| {
        const opt_strs = opt.getOptStrs();
        for (opt_strs) |opt_str| {
            if (std.mem.eql(u8, opt_str, input)) {
                switch (opt) {
                    .to_read_path => {
                        const res = ArgType.to_read_path;
                        break :outer res;
                    },
                }
            }
        }
    } else null;
}

pub fn deinit(self: Self) void {
    if (self.to_read_path) |path| {
        self.allocator.free(path);
    }
}

pub fn getToReadPath(self: Self) ?[]const u8 {
    return self.to_read_path;
}
