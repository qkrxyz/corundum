pub fn TestingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1 / 0",
            &Expression(T){ .binary = .{
                .left = &.{ .number = 1.0 },
                .operation = .division,
                .right = &.{ .number = 0.0 },
            } },
        },
    });
}

pub const Key = enum {
    a,
    b,
};

pub fn @"a ÷ 0"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const bindings = Bindings(Key, T).init(.{});

            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .division) return error.NotApplicable;

            if (expression.binary.right.* == .number and expression.binary.right.number == 0.0) {
                return bindings;
            }

            return error.NoZero;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = bindings;
            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .function = .{
                    .name = "error",
                    .arguments = @constCast(&[_]*const Expression(T){&.{ .variable = "Cannot divide by zero" }}),
                    .body = &.{ .variable = "Division by zero is undefined" },
                } }).clone(allocator),
                .description = try allocator.dupe(u8, ""),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){ .dynamic = .{
        .name = "Division: a ÷ 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

// MARK: tests
test @"a ÷ 0" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"a ÷ 0"(T);

        const one_div_zero = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .division,
            .right = &.{ .number = 0.0 },
        } };

        const zero_div_one = Expression(T){ .binary = .{
            .left = &.{ .number = 0.0 },
            .operation = .division,
            .right = &.{ .number = 1.0 },
        } };

        const one_div_function = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .division,
            .right = &.{ .function = .{
                .name = "x",
                .arguments = @constCast(&[_]*const Expression(T){}),
                .body = null,
            } },
        } };

        var bindings = try Division.dynamic.matches(&one_div_zero);
        try testing.expectEqual(null, bindings.get(.a));
        try testing.expectEqual(null, bindings.get(.b));

        try testing.expectError(error.NoZero, Division.dynamic.matches(&zero_div_one));
        try testing.expectError(error.NoZero, Division.dynamic.matches(&one_div_function));
    }
}

test "a ÷ 0(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"a ÷ 0"(T);

        const one_div_zero = TestingData(T).get("1 / 0").?;

        const bindings = try Division.dynamic.matches(one_div_zero);
        const solution = try Division.dynamic.solve(one_div_zero, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = one_div_zero,
                    .after = &.{ .function = .{
                        .name = "error",
                        .arguments = @constCast(&[_]*const Expression(T){&.{ .variable = "Cannot divide by zero" }}),
                        .body = &.{ .variable = "Division by zero is undefined" },
                    } },
                    .description = "",
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
