const Key = template.Templates.get(.@"core/number/division").key;

pub fn @"a ÷ 1"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.binary.right.number == 1.0) return Bindings(Key, T).init(.{
                .a = expression.binary.left,
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?;

            const solution = try Solution(T).init(1, allocator);
            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try a.clone(allocator),
                .description = "Division by one does nothing",
                .substeps = &.{},
            }).clone(allocator);
            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number division: a ÷ 1",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 999,
    };
}

// TODO tests

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
