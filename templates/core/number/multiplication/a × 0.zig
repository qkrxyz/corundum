const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"a × 0"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates.get(.@"core/number/number").module(T);
            const bindings = Bindings(Key, T).init(.{});

            _ = try number.structure.matches(expression.binary.left);
            _ = try number.structure.matches(expression.binary.right);

            if (expression.binary.left.number != 0.0 and expression.binary.right.number != 0.0) {
                return error.NoZero;
            }

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = bindings;
            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .number = 0 }).clone(allocator),
                .description = try allocator.dupe(u8, "Anything multiplied by 0 is equal to 0"),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    return Variant(Key, T){
        .name = "Number multiplication: a × 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 0,
    };
}

test @"a × 0" {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Multiplication = @"a × 0"(T);

        const one_times_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .number = 0.0 },
        } };

        const zero_times_one = Expression(T){ .binary = .{
            .left = &.{ .number = 0.0 },
            .operation = .multiplication,
            .right = &.{ .number = 1.0 },
        } };

        const one_times_two = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .number = 2.0 },
        } };

        var bindings = try Multiplication.matches(&one_times_zero);
        try testing.expectEqual(null, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        bindings = try Multiplication.matches(&zero_times_one);
        try testing.expectEqual(null, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        try testing.expectError(error.NoZero, Multiplication.matches(&one_times_two));
    }
}

test "a × 0(T).solve" {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Addition = @"a × 0"(T);

        const one_times_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .number = 0.0 },
        } };

        const bindings = try Addition.matches(&one_times_zero);
        const solution = try Addition.solve(&one_times_zero, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = &one_times_zero,
                    .after = &.{ .number = 0.0 },
                    .description = "Anything multiplied by 0 is equal to 0",
                    .substeps = &.{},
                },
            }),
        };

        try testing.expectEqualDeep(expected, solution);
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
