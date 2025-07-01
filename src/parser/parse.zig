pub fn parse_impl(input: []const u8, allocator: std.mem.Allocator) !void {
    const pre = "const _ = ";
    const post = ";";

    const buffer = try std.mem.joinZ(allocator, "", &.{ pre, input, post });
    defer allocator.free(buffer);

    var ast = try std.zig.Ast.parse(allocator, buffer, .zig);
    defer ast.deinit(allocator);

    std.debug.print("{any}\nnodes:\n", .{ast});

    for (0..ast.nodes.len) |i| {
        const data = ast.nodes.get(i);
        const token = ast.tokens.get(data.main_token);

        std.debug.print("{d}: {any}, token: {any} -- '{s}'\n", .{ i, data, token, ast.tokenSlice(data.main_token) });
    }

    const init = ast.nodes.get(@intFromEnum(ast.nodes.get(1).data.opt_node_and_opt_node.@"1"));

    std.debug.print("init expression: {any}, lhs/rhs: {any}\n", .{ init, init.data.node_and_node });
}

test parse_impl {
    // const input = "sqrt(4) + factorial(5) * x";

    // try parse_impl(input, testing.allocator);
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const Expression = expr.Expression;
