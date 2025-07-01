pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{ "(1)", &Expression(T){ .parenthesis = &.{ .number = 1.0 } } },
    });
}

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
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;
            const inner = bindings.get(.inner).?;

            const solution = try Solution(T).init(1, false, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try inner.clone(allocator),
                try allocator.dupe(u8, "Simplify"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .dynamic = .{
            .name = "Rewrite: parenthesis",
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

// MARK: tests
test parenthesis {
    inline for (.{ f32, f64, f128 }) |T| {
        const Parens = parenthesis(T);

        const paren_one = testingData(T).kvs.values[0];

        try testing.expectError(error.NotApplicable, Parens.dynamic.matches(paren_one.parenthesis));

        const bindings = try Parens.dynamic.matches(paren_one);
        try testing.expectEqualDeep(bindings.get(.inner).?, &Expression(T){ .number = 1.0 });
    }
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");
const engine = @import("engine");

const Context = engine.Context;
const Expression = expr.Expression;
const Template = template.Template;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
