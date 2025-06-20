const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"a × 1"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            // In bindings, `a` is the number not equal to one.
            if (expression.binary.left.number == 1.0) {
                bindings.put(.a, expression.binary.right);
            } else if (expression.binary.right.number == 1.0) {
                bindings.put(.a, expression.binary.left);
            } else {
                return error.NoZero;
            }

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?;
            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try a.clone(allocator),
                .description = try allocator.dupe(u8, "Anything multiplied by 1 is equal to itself"),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    return Variant(Key, T){
        .name = "Number multiplication: a × 1",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 999,
    };
}

test @"a × 1" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Multiplication = @"a × 1"(T);

        const two_times_one = Expression(T){ .binary = .{
            .left = &.{ .number = 2.0 },
            .operation = .multiplication,
            .right = &.{ .number = 1.0 },
        } };

        const one_times_two = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .number = 2.0 },
        } };

        const two_times_three = Expression(T){ .binary = .{
            .left = &.{ .number = 2.0 },
            .operation = .multiplication,
            .right = &.{ .number = 3.0 },
        } };

        var bindings = try Multiplication.matches(&two_times_one);
        try testing.expectEqual(two_times_one.binary.left, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        bindings = try Multiplication.matches(&one_times_two);
        try testing.expectEqual(one_times_two.binary.right, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        try testing.expectError(error.NoZero, Multiplication.matches(&two_times_three));
    }
}

test "a × 1(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = @"a × 1"(T);

        const one_times_two = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .number = 2.0 },
        } };

        const bindings = try Addition.matches(&one_times_two);
        const solution = try Addition.solve(&one_times_two, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = &one_times_two,
                    .after = one_times_two.binary.right,
                    .description = "Anything multiplied by 1 is equal to itself",
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
