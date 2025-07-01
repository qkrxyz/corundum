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

pub const Key = enum { a };

pub fn @"a + 0"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            if (expression.* != .binary) return error.NotApplicable;

            const left = expression.binary.left;
            const right = expression.binary.right;

            // In bindings, `a` is the number not equal to zero.
            if (left.* == .number and left.number == 0.0) {
                bindings.put(.a, expression.binary.right);
            } else if (right.* == .number and right.number == 0.0) {
                bindings.put(.a, expression.binary.left);
            } else {
                return error.NoZero;
            }

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;
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
    return Template(Key, T){ .dynamic = .{
        .name = "Addition: a + 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
    } };
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

        var bindings = try Addition.dynamic.matches(&one_plus_zero);
        try testing.expectEqual(one_plus_zero.binary.left, bindings.get(.a));

        bindings = try Addition.dynamic.matches(&zero_plus_one);
        try testing.expectEqual(zero_plus_one.binary.right, bindings.get(.a));

        try testing.expectError(error.NoZero, Addition.dynamic.matches(&one_plus_two));
    }
}

test "a + 0(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = @"a + 0"(T);

        const one_plus_zero = testingData(T).get("1 + 0").?;

        const bindings = try Addition.dynamic.matches(one_plus_zero);
        const solution = try Addition.dynamic.solve(one_plus_zero, bindings, .default, testing.allocator);
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
const engine = @import("engine");

const Context = engine.Context;
const Expression = expr.Expression;
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
