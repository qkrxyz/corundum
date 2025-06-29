pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "x / x",
            &Expression(T){ .binary = .{
                .left = &.{ .variable = "x" },
                .operation = .division,
                .right = &.{ .variable = "x" },
            } },
        },
    });
}

pub const Key = enum {
    a,
};

pub fn @"a ÷ a"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .division) return error.NotApplicable;

            if (expression.binary.left.hash() == expression.binary.right.hash()) return Bindings(Key, T).init(.{ .a = expression.binary.left });

            return error.NoZero;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = bindings;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .number = 1.0 }, allocator),
                try allocator.dupe(u8, "Anything divided by itself is equal to 1"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){ .dynamic = .{
        .name = "Division: a ÷ a",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

// MARK: tests
test @"a ÷ a" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"a ÷ a"(T);

        const one_div_one = Expression(T){ .binary = .{
            .left = &.{ .number = 1.0 },
            .operation = .division,
            .right = &.{ .number = 1.0 },
        } };

        const x_div_x = Expression(T){ .binary = .{
            .left = &.{ .variable = "x" },
            .operation = .division,
            .right = &.{ .variable = "x" },
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

        var bindings = try Division.dynamic.matches(&one_div_one);
        try testing.expectEqualDeep(one_div_one.binary.left, bindings.get(.a).?);

        bindings = try Division.dynamic.matches(&x_div_x);
        try testing.expectEqualDeep(x_div_x.binary.left, bindings.get(.a).?);

        try testing.expectError(error.NoZero, Division.dynamic.matches(&one_div_function));
    }
}

test "a ÷ a(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"a ÷ a"(T);

        const x_div_x = testingData(T).get("x / x").?;

        const bindings = try Division.dynamic.matches(x_div_x);
        const solution = try Division.dynamic.solve(x_div_x, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = x_div_x,
                    .after = &.{ .number = 1.0 },
                    .description = "Anything divided by itself is equal to 1",
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
