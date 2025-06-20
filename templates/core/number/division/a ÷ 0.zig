const Key = template.Templates.get(.@"core/number/division").key;

pub fn @"a ÷ 0"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.binary.right.number == 0.0) return Bindings(Key, T).init(.{});

            return error.NotApplicable;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = bindings;

            const solution = try Solution(T).init(1, allocator);
            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){
                    .function = .{
                        .name = "error",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{ .variable = "Cannot divide by zero" },
                        }),
                        .body = null,
                    },
                }).clone(allocator),
                .description = "",
                .substeps = &.{},
            }).clone(allocator);
            return solution;
        }
    };

    return Variant(Key, T){
        .name = "Number division: a ÷ 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 1000,
    };
}

test @"a ÷ 0" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"a ÷ 0"(T);

        const one_div_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .right = &.{ .number = 0.0 },
            .operation = .division,
        } };

        const bindings = try Division.matches(&one_div_zero);
        const expected = Bindings(Key, T).init(.{});

        try testing.expectEqual(expected, bindings);
    }
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
