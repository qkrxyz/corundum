pub fn Parser(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn preprocess(input: [:0]const u8, allocator: std.mem.Allocator) ![:0]const u8 {
            return preprocess_impl(input, allocator);
        }

        pub fn parse(input: [:0]const u8, allocator: std.mem.Allocator) !ParseResult(T) {
            return parse_impl(T, allocator, input);
        }
    };
}

pub fn ParseResult(comptime T: type) type {
    return struct {
        expression: *const Expression(T),
        variables: *std.StringHashMap(*const Expression(T)),
    };
}

const std = @import("std");
const expr = @import("expr");

const Context = @import("engine").Context;
const Expression = expr.Expression;

const preprocess_impl = @import("parser/preprocess").preprocess;
const parse_impl = @import("parser/parse").parse;
