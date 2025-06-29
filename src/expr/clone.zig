pub fn clone(comptime T: type, expression: *const Expression(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!*const Expression(T) {
    const result = try allocator.create(Expression(T));

    result.* = switch (expression.*) {
        .number, .boolean, .templated => expression.*,

        .variable => |variable| Expression(T){ .variable = try allocator.dupe(u8, variable) },

        .fraction => |fraction| Expression(T){
            .fraction = .{
                .numerator = try clone(T, fraction.numerator, allocator),
                .denominator = try clone(T, fraction.denominator, allocator),
            },
        },

        .equation => |equation| Expression(T){
            .equation = .{
                .sign = equation.sign,
                .left = try clone(T, equation.left, allocator),
                .right = try clone(T, equation.right, allocator),
            },
        },

        .binary => |binary| Expression(T){
            .binary = .{
                .operation = binary.operation,
                .left = try clone(T, binary.left, allocator),
                .right = try clone(T, binary.right, allocator),
            },
        },

        .unary => |unary| Expression(T){
            .unary = .{
                .operation = unary.operation,
                .operand = try clone(T, unary.operand, allocator),
            },
        },

        .function => |function| Expression(T){
            .function = .{
                .name = try allocator.dupe(u8, function.name),
                .arguments = blk: {
                    var arguments: []*const Expression(T) = try allocator.alloc(*const Expression(T), function.arguments.len);
                    for (function.arguments, 0..) |argument, i| {
                        arguments[i] = try clone(T, argument, allocator);
                    }
                    break :blk arguments;
                },
                .body = if (function.body) |body| try clone(T, body, allocator) else null,
            },
        },

        .parenthesis => |inner| Expression(T){
            .parenthesis = try clone(T, inner, allocator),
        },
    };

    return result;
}

const std = @import("std");
const Expression = @import("expr").Expression;
