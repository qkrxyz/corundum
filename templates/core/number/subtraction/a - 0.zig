const Key = template.Templates.get(.@"core/number/subtraction").key;

pub fn @"a - 0"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.binary.right.number != 0.0) {
                return error.NoZero;
            }

            const bindings = Bindings(Key, T).init(.{
                .a = expression.binary.left,
            });
            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?;
            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try a.clone(allocator),
                .description = try allocator.dupe(u8, "Subtracting 0 does nothing"),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    return Variant(Key, T){
        .name = "Number subtraction: a - 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 0,
    };
}

test @"a - 0" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Subtraction = @"a - 0"(T);

        const one_minus_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .subtraction,
            .right = &.{ .number = 0.0 },
        } };

        const zero_minus_one = Expression(T){ .binary = .{
            .left = &.{ .number = 0.0 },
            .operation = .subtraction,
            .right = &.{ .number = 1.0 },
        } };

        const one_minus_two = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .subtraction,
            .right = &.{ .number = 2.0 },
        } };

        const bindings = try Subtraction.matches(&one_minus_zero);
        try testing.expectEqual(one_minus_zero.binary.left, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        try testing.expectError(error.NoZero, Subtraction.matches(&zero_minus_one));
        try testing.expectError(error.NoZero, Subtraction.matches(&one_minus_two));
    }
}

test "a - 0(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Subtraction = @"a - 0"(T);

        const one_minus_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .subtraction,
            .right = &.{ .number = 0.0 },
        } };

        const bindings = try Subtraction.matches(&one_minus_zero);
        const solution = try Subtraction.solve(&one_minus_zero, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = &one_minus_zero,
                    .after = &.{ .number = 1.0 },
                    .description = "Subtracting 0 does nothing",
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
