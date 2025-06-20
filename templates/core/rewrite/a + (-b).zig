pub const Key = enum {
    a,
    b,
};

pub fn @"a + (-b)"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .addition) return error.NotAddition;

            if (expression.binary.right.* == .unary and expression.binary.right.unary.operation != .negation) return error.NotApplicable;

            const bindings = Bindings(Key, T).init(.{
                .a = expression.binary.left,
                .b = expression.binary.right,
            });
            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?;
            const b = bindings.get(.b).?.unary.operand;

            const solution = try Solution(T).init(1, allocator);
            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .binary = .{
                    .left = a,
                    .operation = .subtraction,
                    .right = b,
                } }).clone(allocator),
                .description = try allocator.dupe(u8, "A plus sign and minus sign give together a minus sign"),
                .substeps = &.{},
            }).clone(allocator);

            return solution;
        }
    };

    return Template(Key, T){ .dynamic = .{
        .name = "Rewrite: a + (-b)",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

test @"a + (-b)" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Rewrite = @"a + (-b)"(T);

        const one_minus_minus_x = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .subtraction,
            .right = &.{ .unary = .{
                .operation = .negation,
                .operand = &.{ .variable = "x" },
            } },
        } };

        const bindings = try Rewrite.dynamic.matches(&one_minus_minus_x);

        try testing.expectEqualDeep(one_minus_minus_x.binary.left, bindings.get(.a).?);
        try testing.expectEqualDeep(one_minus_minus_x.binary.right, bindings.get(.b).?);
    }
}

test "a + (-b)(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Rewrite = @"a + (-b)"(T);

        const one_minus_minus_x = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .subtraction,
            .right = &.{ .unary = .{
                .operation = .negation,
                .operand = &.{ .variable = "x" },
            } },
        } };

        const bindings = try Rewrite.dynamic.matches(&one_minus_minus_x);
        const solution = try Rewrite.dynamic.solve(&one_minus_minus_x, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .steps = @constCast(&[_]*const Step(T){&.{
                .before = &one_minus_minus_x,
                .after = &.{ .binary = .{
                    .left = &.{ .number = 1.0 },
                    .operation = .subtraction,
                    .right = &.{ .variable = "x" },
                } },
                .description = "A plus sign and minus sign give together a minus sign",
                .substeps = &.{},
            }}),
        };

        try testing.expectEqualDeep(expected, solution);
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
