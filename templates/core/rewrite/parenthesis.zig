pub const Key = enum {
    inner,
};

pub fn parenthesis(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .parenthesis) return error.NotApplicable;

            const bindings = Bindings(Key, T).init(.{
                .inner = expression.parenthesis,
            });
            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const inner = bindings.get(.inner).?;

            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try inner.clone(allocator),
                .description = try allocator.dupe(u8, "Simplify"),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .dynamic = .{
            .name = "Rewrite: parenthesis",
            .matches = Impl.matches,
            .solve = Impl.solve,
            .variants = &.{},
        },
    };
}

// MARK: tests
test parenthesis {
    inline for (.{ f32, f64, f128 }) |T| {
        const Parens = parenthesis(T);

        const one = Expression(T){ .number = 1.0 };
        const paren_one = Expression(T){ .parenthesis = &one };

        try testing.expectError(error.NotApplicable, Parens.dynamic.matches(&one));

        const bindings = try Parens.dynamic.matches(&paren_one);
        try testing.expectEqualDeep(bindings.get(.inner).?, &one);
    }
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Template = template.Template;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
