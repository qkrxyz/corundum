pub fn parse(comptime T: type, allocator: std.mem.Allocator, input: [:0]const u8) !ParseResult(T) {
    var ast = try std.zig.Ast.parse(allocator, input, .zig);
    defer ast.deinit(allocator);

    const start = ast.nodes.get(ast.extra_data[@intFromEnum(ast.nodes.get(0).data.extra_range.start)]);
    const right = start.data.opt_node_and_opt_node.@"1".unwrap().?;

    var variables: std.StringHashMap(*const Expression(T)) = .init(allocator);

    return .{
        .expression = try translate(T, &variables, &ast, @intFromEnum(right), allocator),
        .variables = &variables,
    };
}

const std = @import("std");
const expr = @import("expr");
const parser = @import("parser");
const translate = @import("parser/translate").translate;

const testing = std.testing;
const Expression = expr.Expression;
const Parser = parser.Parser;
const ParseResult = parser.ParseResult;
