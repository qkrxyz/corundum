pub fn Engine(comptime T: type) type {
    return struct {
        const Self = @This();

        context: Context(T) = .default,
        allocator: std.mem.Allocator,

        pub fn init(context: Context(T), allocator: std.mem.Allocator) Self {
            return Self{
                .context = context,
                .allocator = allocator,
            };
        }

        pub fn run() !void {
            unreachable;
        }
    };
}

const std = @import("std");
const expr = @import("expr");

pub const Context = @import("engine/context").Context;
