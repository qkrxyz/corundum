pub fn Parser(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        input: [:0]const u8,
        context: Context(T),

        pub fn init(input: [:0]const u8, allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .input = input,
                .context = .default,
            };
        }

        pub fn preprocess(self: *Self) ![:0]const u8 {
            return preprocess_impl(T, self);
        }

        pub fn parse(self: *Self, preprocessed: [:0]const u8) !*const expr.Expression(T) {
            return parse_impl(T, self, preprocessed);
        }
    };
}

const std = @import("std");
const expr = @import("expr");

const Context = @import("engine").Context;
const Expression = expr.Expression;

const preprocess_impl = @import("parser/preprocess").preprocess;
const parse_impl = @import("parser/parse").parse;
