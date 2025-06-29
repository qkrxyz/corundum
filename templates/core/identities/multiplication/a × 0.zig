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

pub const Key = enum {};

pub fn @"a × 0"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const bindings = Bindings(Key, T).init(.{});

            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .multiplication) return error.NotApplicable;

            if ((expression.binary.left.* == .number and expression.binary.left.number == 0.0) or (expression.binary.right.* == .number and expression.binary.right.number == 0.0)) {
                return bindings;
            }

            return error.NoZero;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
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

    // MARK: template
    return Template(Key, T){ .dynamic = .{
        .name = "Multiplication: a × 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

// MARK: tests
test @"a × 0" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Multiplication = @"a × 0"(T);

        const one_times_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .number = 0.0 },
        } };

        const zero_times_x = Expression(T){ .binary = .{
            .left = &.{ .number = 0.0 },
            .operation = .multiplication,
            .right = &.{ .variable = "x" },
        } };

        const one_times_function = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .function = .{
                .name = "x",
                .arguments = @constCast(&[_]*const Expression(T){}),
                .body = null,
            } },
        } };

        var bindings = try Multiplication.dynamic.matches(&one_times_zero);
        bindings = try Multiplication.dynamic.matches(&zero_times_x);

        try testing.expectError(error.NoZero, Multiplication.dynamic.matches(&one_times_function));
    }
}

test "a × 0(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Multiplication = @"a × 0"(T);

        const one_times_zero = testingData(T).get("1 * 0").?;

        const bindings = try Multiplication.dynamic.matches(one_times_zero);
        const solution = try Multiplication.dynamic.solve(one_times_zero, bindings, testing.allocator);
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
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
