pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "24 / 0",
            &Expression(T){
                .function = .{
                    .name = "divFloor",
                    .arguments = @constCast(&[_]*const Expression(T){
                        &.{ .number = 24.0 },
                        &.{ .number = 0.0 },
                    }),
                    .body = null,
                },
            },
        },
    });
}

const Key = template.Templates.get(.@"builtin/functions/divFloor").key;

pub fn @"a ÷ 0"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.function.arguments[1].number == 0.0) return Bindings(Key, T).init(.{});

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = bindings;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{
                    .function = .{
                        .name = "error",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{ .variable = "Cannot divide by zero" },
                        }),
                        .body = &.{ .variable = "Division by zero is undefined" },
                    },
                }, allocator),
                "",
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Builtin function: number division, rounded down: a ÷ 0",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 1000,
    };
}

// MARK: tests
test @"a ÷ 0" {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Division = @"a ÷ 0"(T);

        const twenty_four_div_0 = testingData(T).get("24 / 0").?;

        const bindings = try Division.matches(twenty_four_div_0);
        const solution = try Division.solve(twenty_four_div_0, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = twenty_four_div_0,
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
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
