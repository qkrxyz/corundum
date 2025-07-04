pub fn find(comptime T: type, haystack: *const Expression(T), needle: *const Expression(T)) ?*const Expression(T) {
    switch (haystack.*) {
        .number, .variable, .boolean => if (eql(T, haystack, needle)) return haystack else return null,

        .fraction => {
            if (find(T, haystack.fraction.numerator, needle)) |result| return result;
            if (find(T, haystack.fraction.denominator, needle)) |result| return result;

            return null;
        },

        .binary => {
            if (find(T, haystack.binary.left, needle)) |result| return result;
            if (find(T, haystack.binary.right, needle)) |result| return result;

            return null;
        },

        .equation => {
            if (find(T, haystack.equation.left, needle)) |result| return result;
            if (find(T, haystack.equation.right, needle)) |result| return result;

            return null;
        },

        .unary => return find(T, haystack.unary.operand, needle),

        .function => {
            for (haystack.function.arguments) |argument| {
                if (find(T, argument, needle)) |result| return result;
            }

            if (haystack.function.body) |body| return find(T, body, needle);

            return null;
        },

        .templated => unreachable,

        .parenthesis => return find(T, haystack.parenthesis, needle),
    }
}

const std = @import("std");
const expr = @import("expr");
const eql = @import("expr/eql").eql;

const Expression = expr.Expression;
