pub fn parse(comptime T: type, self: *Parser(T), input: [:0]const u8) !*const Expression(T) {
    var ast = try std.zig.Ast.parse(self.allocator, input, .zig);
    defer ast.deinit(self.allocator);

    const start = ast.nodes.get(ast.extra_data[@intFromEnum(ast.nodes.get(0).data.extra_range.start)]);
    const right = start.data.opt_node_and_opt_node.@"1".unwrap().?;

    return translate(T, self.context, &ast, @intFromEnum(right), self.allocator);
}

test parse {}

const std = @import("std");
const expr = @import("expr");
const parser = @import("parser");
const translate = @import("parser/translate").translate;

const testing = std.testing;
const Expression = expr.Expression;
const Parser = parser.Parser;
