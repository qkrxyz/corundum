pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "9 / 9", &Expression(T){
                .function = .{
                    .name = "divFloor",
                    .arguments = @constCast(&[_]*const Expression(T){
                        &.{ .number = 9.0 },
                        &.{ .number = 9.0 },
                    }),
                    .body = null,
                },
            },
        },
    });
}

const Key = template.Templates.get(.@"builtin/functions/divFloor").key;

pub fn @"a eq b"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const arguments = expression.function.arguments;

            if (arguments[0].number == arguments[1].number) return Bindings(Key, T).init(.{
                .a = arguments[0],
                .b = arguments[1],
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .number = 1.0 }, allocator),
                try std.fmt.allocPrint(allocator, "Since {d} is equal to {d}, the result is 1.", .{ a, b }),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Builtin function: number division, rounded down: a = b",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 50,
    };
}

// TODO tests
test @"a eq b" {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Division = @"a eq b"(T);

        const nine = testingData(T).get("9 / 9").?;

        const bindings = try Division.matches(nine);
        const solution = try Division.solve(nine, bindings, .default, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = nine,
                    .after = &.{ .number = 1.0 },
                    .description = "Since 9 is equal to 9, the result is 1.",
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
