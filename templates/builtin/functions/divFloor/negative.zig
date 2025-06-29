pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "9 / -5", &Expression(T){ .function = .{
                .name = "divFloor",
                .arguments = @constCast(&[_]*const Expression(T){
                    &.{ .number = 9.0 },
                    &.{ .number = -5.0 },
                }),
                .body = null,
            } },
        },
    });
}

const Key = template.Templates.get(.@"builtin/functions/divFloor").key;

pub fn negative(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const arguments = expression.function.arguments;

            // e.g. -5, 3 -> true != false, which is true; we only need one number to be negative. (because -a/-b = a/b)
            if ((arguments[0].number < 0.0) != (arguments[1].number < 0.0)) return Bindings(Key, T).init(.{
                .a = arguments[0],
                .b = arguments[1],
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = expression;

            const divFloor = template.Templates.get(.@"builtin/functions/divFloor").module(T);
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const division = try divFloor.structure.solve(
                &.{
                    .function = .{
                        .name = "divFloor",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{ .number = @abs(a) },
                            &.{ .number = @abs(b) },
                        }),
                        .body = null,
                    },
                },
                Bindings(Key, T).init(.{
                    .a = &.{ .number = @abs(a) },
                    .b = &.{ .number = @abs(b) },
                }),
                allocator,
            );

            const last = division.steps[division.steps.len - 1].after;
            const x = last.number;
            const remainder = (x + 1) * b - a;

            const solution = try Solution(T).init(division.steps.len + 1, true, allocator);

            @memcpy(solution.steps[0..division.steps.len], division.steps);
            defer allocator.free(division.steps);

            solution.steps[solution.steps.len - 1] = try Step(T).init(
                try last.clone(allocator),
                try Expression(T).init(.{ .number = -last.number - 1 }, allocator),
                try std.fmt.allocPrint(allocator, "Since our original input contained negative numbers, we also have to change the sign of our result and also subtract one.\n\nThis is because $-{d} \\times {d} + {d}$ (the remainder) $= -{d} + {d} = -{d}$", .{ x + 1, b, remainder, (x + 1) * b, remainder, a }),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Builtin function: number division, rounded down: negative parameters",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 50,
    };
}

// MARK: tests
test negative {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = negative(T);

        const nine_div_minus_five = testingData(T).get("9 / -5").?;

        const bindings = try Division.matches(nine_div_minus_five);
        const solution = try Division.solve(nine_div_minus_five, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = &.{ .number = 1.0 },
                    .after = &.{ .number = 1.0 },
                    .description = "Figure out the magnitude of the result",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 5.0 },
                                .right = &.{ .number = 1.0 },
                            } },
                            .after = &.{ .number = 5.0 },
                            .description = "Since 5 is less than or equal to 9, we add 1 decimal place to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 5.0 },
                                .right = &.{ .number = 10.0 },
                            } },
                            .after = &.{ .number = 5.0 },
                            .description = "Since 50 is more than 9, divide the multiplier by 10",
                            .substeps = &.{},
                        },
                    }),
                },
                &.{
                    .before = &.{ .number = 1.0 },
                    .after = &.{ .number = 1.0 },
                    .description = "Refine the search",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 5 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 1 },
                                        &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = 1.0 },
                                            .right = &.{ .binary = .{
                                                .operation = .subtraction,
                                                .left = &.{ .number = 1.0 },
                                                .right = &.{ .number = 1.0 },
                                            } },
                                        } },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 5.0 },
                            .description = "Since 10 is more than 9, we go back to the previous multiplier and since the magnitude is equal to 1, we found the answer.",
                            .substeps = &.{},
                        },
                    }),
                },
                &.{
                    .before = &.{ .number = 1.0 },
                    .after = &.{ .number = -2.0 },
                    .description = "Since our original input contained negative numbers, we also have to change the sign of our result and also subtract one.\n\nThis is because $-2 \\times -5 + -19$ (the remainder) $= --10 + -19 = -9$",
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
