pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "5 / 9", &Expression(T){
                .function = .{
                    .name = "divFloor",
                    .arguments = @constCast(&[_]*const Expression(T){
                        &.{ .number = 5.0 },
                        &.{ .number = 9.0 },
                    }),
                    .body = null,
                },
            },
        },
    });
}

const Key = template.Templates.get(.@"builtin/functions/divFloor").key;

pub fn @"a ＜ b"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const arguments = expression.function.arguments;

            if (@abs(arguments[0].number) < @abs(arguments[1].number)) return Bindings(Key, T).init(.{
                .a = arguments[0],
                .b = arguments[1],
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .number = 0.0 }, allocator),
                try std.fmt.allocPrint(allocator, "Since {d} is smaller than {d}, the result is 0.", .{ a, b }),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Builtin function: number division, rounded down: a ＜ 1",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 50,
    };
}

// MARK: tests
test @"a ＜ b" {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Division = @"a ＜ b"(T);

        const five_div_nine = testingData(T).get("5 / 9").?;

        const bindings = try Division.matches(five_div_nine);
        const solution = try Division.solve(five_div_nine, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = five_div_nine,
                    .after = &.{ .number = 0.0 },
                    .description = "Since 5 is smaller than 9, the result is 0.",
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
