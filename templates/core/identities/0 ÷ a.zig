pub fn TestingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "0 / x",
            &Expression(T){ .binary = .{
                .left = &.{ .number = 0.0 },
                .operation = .division,
                .right = &.{ .variable = "x" },
            } },
        },
    });
}

pub const Key = enum {
    a,
};

pub fn @"0 ÷ a"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .division) return error.NotApplicable;

            if (expression.binary.left.* == .number and expression.binary.left.number == 0.0) return Bindings(Key, T).init(.{ .a = expression.binary.right });

            return error.NoZero;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = bindings;

            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .number = 0.0 }).clone(allocator),
                .description = try allocator.dupe(u8, "0 divided by anything is equal to 0"),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){ .dynamic = .{
        .name = "Division: 0 ÷ a",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

// MARK: tests
test @"0 ÷ a" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"0 ÷ a"(T);

        const zero_div_one = Expression(T){ .binary = .{
            .left = &.{ .number = 0.0 },
            .operation = .division,
            .right = &.{ .number = 1.0 },
        } };

        const zero_div_x = Expression(T){ .binary = .{
            .left = &.{ .number = 0.0 },
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

        var bindings = try Division.dynamic.matches(&zero_div_one);
        try testing.expectEqualDeep(zero_div_one.binary.right, bindings.get(.a).?);

        bindings = try Division.dynamic.matches(&zero_div_x);
        try testing.expectEqualDeep(zero_div_x.binary.right, bindings.get(.a).?);

        try testing.expectError(error.NoZero, Division.dynamic.matches(&one_div_function));
    }
}

test "0 ÷ a(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"0 ÷ a"(T);

        const zero_div_x = TestingData(T).get("0 / x").?;

        const bindings = try Division.dynamic.matches(zero_div_x);
        const solution = try Division.dynamic.solve(zero_div_x, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = zero_div_x,
                    .after = &.{ .number = 0.0 },
                    .description = "0 divided by anything is equal to 0",
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
