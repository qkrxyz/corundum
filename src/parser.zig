pub fn Parser(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        input: [:0]const u8,

        pub fn init(input: [:0]const u8, allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .input = input,
            };
        }

        pub fn preprocess(self: *Self) ![]u8 {
            return preprocess_impl(T, self);
        }

        pub fn parse(self: *Self) !void {
            return parse_impl(T, self);
        }
    };
}

const std = @import("std");
const expr = @import("expr");

const Expression = expr.Expression;

const preprocess_impl = @import("parser/preprocess").preprocess;
const parse_impl = @import("parser/parse").parse;
