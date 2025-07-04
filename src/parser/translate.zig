pub fn translate(
    comptime T: type,
    context: Context(T),
    ast: *const std.zig.Ast,
    index: usize,
    allocator: std.mem.Allocator,
) !*const Expression(T) {
    const node = ast.nodes.get(index);
    switch (node.tag) {
        // left + right, left - right, left * right, left / right, left % right
        .add, .sub, .mul, .div, .mod => {
            const left_index, const right_index = node.data.node_and_node;

            const left = try translate(T, context, ast, @intFromEnum(left_index), allocator);
            const right = try translate(T, context, ast, @intFromEnum(right_index), allocator);

            return Expression(T).clone(
                &.{ .binary = .{
                    .left = left,
                    .right = right,
                    .operation = switch (node.tag) {
                        .add => .addition,
                        .sub => .subtraction,
                        .mul => .multiplication,
                        .div => .division,
                        .mod => .modulus,
                        else => unreachable,
                    },
                } },
                allocator,
            );
        },

        // `==` -> Expression(T){ .equation = ... }
        .equal_equal => {
            const left_index, const right_index = node.data.node_and_node;

            const left = try translate(T, context, ast, @intFromEnum(left_index), allocator);
            const right = try translate(T, context, ast, @intFromEnum(right_index), allocator);

            // an assignment, since the variable from the left-hand side doesn't repeat in the right side
            if (left.* == .variable and right.find(left) == null) {
                // try context.variables.put(left.variable, right);
                return Expression(T).clone(
                    &.{ .equation = .{
                        .left = left,
                        .right = right,
                        .sign = .equals,
                    } },
                    allocator,
                );
            }

            @panic("TODO: equality");
        },

        // number
        .number_literal => {
            const value = std.fmt.parseFloat(T, ast.tokenSlice(node.main_token)) catch unreachable;

            return Expression(T).init(.{ .number = value }, allocator);
        },

        // variable
        .identifier => {
            var identifier = ast.tokenSlice(node.main_token);

            if (std.mem.eql(u8, "@\"", identifier[0..2]) and identifier[identifier.len - 1] == '\"') {
                identifier = identifier[2 .. identifier.len - 1];
            }

            return Expression(T).init(.{ .variable = identifier }, allocator);
        },

        // function call, one argument
        .call_one, .call_one_comma => {
            const function, const parameter = node.data.node_and_opt_node;

            const function_node = ast.nodes.get(@intFromEnum(function));
            const function_name = ast.tokenSlice(function_node.main_token);

            if (parameter == .none) {
                return Expression(T).init(.{ .function = .{
                    .name = function_name,
                    .arguments = &.{},
                    .body = null,
                } }, allocator);
            }

            const parameter_expr = try translate(T, context, ast, @intFromEnum(parameter.unwrap().?), allocator);

            const arguments = try allocator.alloc(*const Expression(T), 1);
            arguments[0] = parameter_expr;

            const expression = try allocator.create(Expression(T));
            expression.* = .{ .function = .{
                .name = try allocator.dupe(u8, function_name),
                .arguments = arguments,
                .body = null,
            } };

            return expression;
        },

        else => @panic("unimplemented"),
    }

    unreachable;
}

const std = @import("std");
const expr = @import("expr");
const parser = @import("parser");
const engine = @import("engine");

const Expression = expr.Expression;
const Parser = parser.Parser;
const Context = engine.Context;
