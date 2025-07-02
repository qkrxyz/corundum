pub fn Parser(comptime T: type) type {
    return struct {
        const Self = @This();

        const pre = "const _ = ";
        const post = ";";

        allocator: std.mem.Allocator,
        input: [:0]const u8,
        buffer: std.ArrayList(u8),

        pub fn init(input: [:0]const u8, allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .input = input,
                .buffer = .init(allocator),
            };
        }

        pub fn preprocess(self: *Self) !void {
            return preprocess_impl(T, self, pre, post);
        }

        pub fn parse(self: *Self) !void {
            return parse_impl(T, self);
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }
    };
}

const std = @import("std");
const expr = @import("expr");

const Expression = expr.Expression;

const preprocess_impl = @import("parser/preprocess").preprocess;
const parse_impl = @import("parser/parse").parse;
