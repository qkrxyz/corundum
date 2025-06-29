pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1 + 0", &Expression(T){ .binary = .{
                .left = &.{ .number = 1.0 },
                .operation = .addition,
                .right = &.{ .number = 0.0 },
            } },
        },
    });
}

const Key = template.Templates.get(.@"core/number/addition").key;

pub fn @"a + 0"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            // In bindings, `a` is the number not equal to zero.
            if (expression.binary.left.number == 0.0) {
                bindings.put(.a, expression.binary.right);
            } else if (expression.binary.right.number == 0.0) {
                bindings.put(.a, expression.binary.left);
            } else {
                return error.NoZero;
            }
            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try a.clone(allocator),
                try allocator.dupe(u8, "Adding 0 does nothing"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number addition: a + 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 0,
    };
}

// MARK: tests
test @"a + 0" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = @"a + 0"(T);

        const one_plus_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .addition,
            .right = &.{ .number = 0.0 },
        } };

        const zero_plus_one = Expression(T){ .binary = .{
            .left = &.{ .number = 0.0 },
            .operation = .addition,
            .right = &.{ .number = 1.0 },
        } };

        const one_plus_two = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .addition,
            .right = &.{ .number = 2.0 },
        } };

        var bindings = try Addition.matches(&one_plus_zero);
        try testing.expectEqual(one_plus_zero.binary.left, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        bindings = try Addition.matches(&zero_plus_one);
        try testing.expectEqual(zero_plus_one.binary.right, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        try testing.expectError(error.NoZero, Addition.matches(&one_plus_two));
    }
}

test "a + 0(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = @"a + 0"(T);

        const one_plus_zero = testingData(T).get("1 + 0").?;

        const bindings = try Addition.matches(one_plus_zero);
        const solution = try Addition.solve(one_plus_zero, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = one_plus_zero,
                    .after = &.{ .number = 1.0 },
                    .description = "Adding 0 does nothing",
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
