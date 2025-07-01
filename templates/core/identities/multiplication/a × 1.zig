pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "x * 1", &Expression(T){ .binary = .{
                .left = &.{ .variable = "x" },
                .operation = .multiplication,
                .right = &.{ .number = 1.0 },
            } },
        },
    });
}

pub const Key = enum {
    a,
};

pub fn @"a × 1"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .multiplication) return error.NotApplicable;

            const left = expression.binary.left;
            const right = expression.binary.right;

            if (left.* == .number and left.number == 1.0 and !(right.* == .number and right.number == 0.0)) {
                return Bindings(Key, T).init(.{ .a = expression.binary.right });
            } else if (right.* == .number and right.number == 1.0 and !(left.* == .number and left.number == 0.0)) {
                return Bindings(Key, T).init(.{ .a = expression.binary.left });
            }

            return error.NoOne;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;

            const a = bindings.get(.a).?;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try a.clone(allocator),
                try allocator.dupe(u8, "Anything multiplied by 1 is equal to itself"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){ .dynamic = .{
        .name = "Multiplication: a × 1",
        .matches = Impl.matches,
        .solve = Impl.solve,
    } };
}

// MARK: tests
test @"a × 1" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Multiplication = @"a × 1"(T);

        const one_times_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .multiplication,
            .right = &.{ .number = 0.0 },
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

        const x_times_one = testingData(T).get("x * 1").?;

        var bindings = try Multiplication.dynamic.matches(x_times_one);
        try testing.expectEqual(x_times_one.binary.left, bindings.get(.a));

        bindings = try Multiplication.dynamic.matches(&one_times_function);
        try testing.expectEqual(one_times_function.binary.right, bindings.get(.a));

        try testing.expectError(error.NoOne, Multiplication.dynamic.matches(&one_times_zero));
    }
}

test "a × 1(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Multiplication = @"a × 1"(T);

        const x_times_one = testingData(T).get("x * 1").?;

        const bindings = try Multiplication.dynamic.matches(x_times_one);
        const solution = try Multiplication.dynamic.solve(x_times_one, bindings, .default, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = x_times_one,
                    .after = &.{ .variable = "x" },
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
const engine = @import("engine");

const Context = engine.Context;
const Expression = expr.Expression;
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
