pub fn eql(comptime T: type, left: *const Expression(T), right: *const Expression(T)) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) return false;

    return switch (left.*) {
        .number => left.number == right.number,
        .variable => std.mem.eql(u8, left.variable, right.variable),
        .boolean => left.boolean == right.boolean,

        // zig fmt: off
        .fraction => eql(T, left.fraction.numerator, right.fraction.numerator)
                and eql(T, left.fraction.denominator, right.fraction.denominator),


        .equation => left.equation.sign == right.equation.sign
                and eql(T, left.equation.left, right.equation.left)
                and eql(T, left.equation.right, right.equation.right),

        .binary => left.binary.operation == right.binary.operation
                and eql(T, left.binary.left, right.binary.left)
                and eql(T, left.binary.right, right.binary.right),

        .unary => left.unary.operation == right.unary.operation
                and eql(T, left.unary.operand, right.unary.operand),

        .function => {
            const same_body = if(left.function.body == null and right.function.body == null) eql(T, left.function.body orelse return false, right.function.body orelse return false) else false;

            return std.mem.eql(u8, left.function.name, right.function.name)
                and same_body
                and {
                    for (left.function.arguments, right.function.arguments) |lhs, rhs| {
                        if(!eql(T, lhs, rhs)) return false;
                    }

                    return true;
                };
        },

        // zig fmt: on
        .templated => unreachable,
        .parenthesis => eql(T, left.parenthesis, right.parenthesis),
    };
}

const std = @import("std");
const expr = @import("expr");

const Expression = expr.Expression;
