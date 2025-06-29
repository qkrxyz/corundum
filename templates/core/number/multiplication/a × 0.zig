pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1 * 0", &Expression(T){ .binary = .{
                .left = &.{ .number = 1.0 },
                .operation = .multiplication,
                .right = &.{ .number = 0.0 },
            } },
        },
    });
}

const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"a × 0"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const bindings = Bindings(Key, T).init(.{});

            if (expression.binary.left.number != 0.0 and expression.binary.right.number != 0.0) {
                return error.NoZero;
            }

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = bindings;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .number = 0.0 }, allocator),
                try allocator.dupe(u8, "Anything multiplied by 0 is equal to 0"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number multiplication: a × 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 1000,
    };
}

// MARK: tests
test @"a × 0" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Multiplication = @"a × 0"(T);

        const one_times_zero = testingData(T).get("1 * 0").?;

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

        var bindings = try Multiplication.matches(one_times_zero);
        try testing.expectEqual(null, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        bindings = try Multiplication.matches(&zero_times_one);
        try testing.expectEqual(null, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        try testing.expectError(error.NoZero, Multiplication.matches(&one_times_two));
    }
}

test "a × 0(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Multiplication = @"a × 0"(T);

        const one_times_zero = testingData(T).get("1 * 0").?;

        const bindings = try Multiplication.matches(one_times_zero);
        const solution = try Multiplication.solve(one_times_zero, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = one_times_zero,
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
