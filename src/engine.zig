pub fn Engine(comptime T: type) type {
    return struct {
        const Self = @This();

        expression: *const expr.Expression(T),
        allocator: std.mem.Allocator,

        pub fn init(input: *const expr.Expression(T), allocator: std.mem.Allocator) Self {
            Self.expression = input;

            return Self{
                .expression = input,
                .allocator = allocator,
            };
        }

        pub fn run() !void {

        }
    };
}

const std = @import("std");
const expr = @import("expr");
