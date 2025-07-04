pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "30 / 1",
            &Expression(T){
                .function = .{
                    .name = "divFloor",
                    .arguments = @constCast(&[_]*const Expression(T){
                        &.{ .number = 30.0 },
                        &.{ .number = 1.0 },
                    }),
                    .body = null,
                },
            },
        },
    });
}

const Key = template.Templates.get(.@"builtin/functions/divFloor").key;

pub fn @"a ÷ 1"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.function.arguments[1].number == 1.0) return Bindings(Key, T).init(.{
                .a = expression.function.arguments[0],
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;
            const a = bindings.get(.a).?;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try a.clone(allocator),
                try allocator.dupe(u8, "Division by one does nothing"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Builtin function: number division, rounded down: a ÷ 1",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 999,
    };
}

// MARK: tests
test @"a ÷ 1" {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Division = @"a ÷ 1"(T);

        const thirty_div_1 = testingData(T).get("30 / 1").?;

        const bindings = try Division.matches(thirty_div_1);
        const solution = try Division.solve(thirty_div_1, bindings, .default, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = thirty_div_1,
                    .after = &.{ .number = 30.0 },
                    .description = "Division by one does nothing",
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
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
