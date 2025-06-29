pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1.5 * 2", &Expression(T){ .binary = .{
                .operation = .multiplication,
                .left = &.{ .number = 1.5 },
                .right = &.{ .number = 2.0 },
            } },
        },
    });
}

const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"float, int"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            const is_a_integer = @rem(expression.binary.left.number, 1.0) == 0.0;
            const is_b_integer = @rem(expression.binary.right.number, 1.0) == 0.0;

            if (is_a_integer == is_b_integer) {
                return error.NoFloatAndInt;
            }

            // In bindings, `a` is the floating-point number.
            if (is_a_integer) {
                bindings.put(.a, expression.binary.right);
                bindings.put(.b, expression.binary.left);
            } else {
                bindings.put(.a, expression.binary.left);
                bindings.put(.b, expression.binary.right);
            }

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const I = @Type(.{ .int = .{ .bits = @bitSizeOf(T), .signedness = .unsigned } });

            const a, const b = .{ bindings.get(.a).?.number, bindings.get(.b).?.number };
            const solution = try Solution(T).init(if ((a < 0.0) ^ (b < 0.0)) 4 else 3, true, allocator);

            // Here, a is the floating-point number.
            // Let c be equal to the whole part of a and d be equal to the fractional part of a.
            // (c + d) * b = bc + bd <=> c + d = a
            const c = @divFloor(a, 1.0);
            const d = a - c;

            // MARK: expand
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(
                    .{ .binary = .{
                        .operation = .addition,
                        .left = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = b },
                            .right = &.{ .number = c },
                        } },
                        .right = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = b },
                            .right = &.{ .number = d },
                        } },
                    } },
                    allocator,
                ),
                try allocator.dupe(u8,
                    \\Expand
                    \\
                    \\We can rewrite $a * b$ as $b * c + b * d = bc + bd$, where $c$ is the whole part of $a$ and $d$ is the fractional part.
                ),
                &.{},
                allocator,
            );

            // MARK: simplify
            const bc = b * c;
            const bd = b * d;

            solution.steps[1] = try Step(T).init(
                try solution.steps[0].after.clone(allocator),
                try Expression(T).init(.{ .binary = .{
                    .operation = .addition,
                    .left = &.{ .number = bc },
                    .right = &.{ .number = bd },
                } }, allocator),

                try allocator.dupe(u8, "Simplify"),
                blk: {
                    const substeps = try allocator.alloc(*const Step(T), 2);

                    // always integer * integer, always 1 step
                    const integer_integer = try template.Templates.get(.@"core/number/multiplication/int, int")(T).solve(
                        solution.steps[0].after.binary.left,
                        Bindings(Key, T).init(.{
                            .a = solution.steps[0].after.binary.left.binary.left,
                            .b = solution.steps[0].after.binary.left.binary.right,
                        }),
                        allocator,
                    );
                    defer allocator.free(integer_integer.steps);
                    substeps[0] = integer_integer.steps[0];

                    // always float * integer, cannot be called recursively
                    substeps[1] = try (Step(T){
                        .before = try Expression(T).init(.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = b },
                            .right = &.{ .number = d },
                        } }, allocator),
                        .after = try Expression(T).init(.{ .number = bd }, allocator),
                        .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ b, d }),
                        .substeps = float_integer: {
                            const float_integer_steps = try allocator.alloc(*const Step(T), 2);

                            // reinterpret d as integer; multiply
                            const d_str = try std.fmt.allocPrint(allocator, "{d}", .{d});
                            defer allocator.free(d_str);

                            const d_int = try std.fmt.parseFloat(T, d_str[2..]);
                            const multiplied = d_int * b;

                            float_integer_steps[0] = try (Step(T){
                                .before = try Expression(T).init(.{ .binary = .{
                                    .operation = .multiplication,
                                    .left = &.{ .number = d_int },
                                    .right = &.{ .number = b },
                                } }, allocator),
                                .after = try Expression(T).init(.{ .number = multiplied }, allocator),

                                .description = try std.fmt.allocPrint(allocator, "Multiply the fractional part of {d} (as if it was an integer) with {d}", .{ d, b }),
                                .substeps = &.{},
                            }).clone(allocator);

                            // shift
                            const b_len = b_len_blk: {
                                const truncated: I = @intFromFloat(@trunc(b));

                                var i: I = 0;
                                while (try std.math.powi(I, 10, i) <= truncated) : (i += 1) {}

                                break :b_len_blk i;
                            };
                            const shift: I = @intCast(b_len + d_str[2..].len);

                            float_integer_steps[1] = try (Step(T){
                                .before = try float_integer_steps[0].after.clone(allocator),
                                .after = try Expression(T).init(.{
                                    .number = multiplied / @as(T, @floatFromInt(try std.math.powi(I, 10, shift - 1))),
                                }, allocator),
                                .description = try std.fmt.allocPrint(allocator, "Move the decimal point left by {d} place(-s)", .{shift - 1}),
                                .substeps = &.{},
                            }).clone(allocator);

                            break :float_integer float_integer_steps;
                        },
                    }).clone(allocator);

                    break :blk substeps;
                },
                allocator,
            );

            // MARK: add
            // TODO refactor
            const addition = template.Templates.get(.@"core/number/addition");
            const new_bindings = Bindings(addition.key, T).init(.{
                .a = solution.steps[1].after.binary.left,
                .b = solution.steps[1].after.binary.right,
            });

            const addition_result = try addition.module(T).structure.solve(solution.steps[1].after, new_bindings, allocator);
            defer allocator.free(addition_result.steps);

            for (addition_result.steps, 0..) |step, i| {
                solution.steps[2 + i] = step;
            }

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number multiplication: float × integer",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 2,
    };
}

// MARK: tests
test "float, int(T).matches" {
    const Multiplication = @"float, int"(f64);

    const two_times_three = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 3.0 },
    } };

    const three_halves_times_two = testingData(f64).get("1.5 * 2").?;

    const half_of_quarter = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 0.5 },
        .right = &.{ .number = 0.25 },
    } };

    try testing.expectEqual(Bindings(Key, f64).init(.{
        .a = three_halves_times_two.binary.left,
        .b = three_halves_times_two.binary.right,
    }), Multiplication.matches(three_halves_times_two));

    try testing.expectError(error.NoFloatAndInt, Multiplication.matches(&two_times_three));
    try testing.expectError(error.NoFloatAndInt, Multiplication.matches(&half_of_quarter));
}

test "float, int(T).solve" {
    const Multiplication = @"float, int"(f64);

    const three_halves_times_two = testingData(f64).get("1.5 * 2").?;

    const bindings = try Multiplication.matches(three_halves_times_two);
    const solution = try Multiplication.solve(three_halves_times_two, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .is_final = true,
        .steps = @constCast(&[_]*const Step(f64){
            // step 1: rewrite
            &.{
                .before = three_halves_times_two,
                .after = &.{ .binary = .{
                    .operation = .addition,
                    .left = &.{ .binary = .{
                        .operation = .multiplication,
                        .left = &.{ .number = 2.0 },
                        .right = &.{ .number = 1.0 },
                    } },
                    .right = &.{ .binary = .{
                        .operation = .multiplication,
                        .left = &.{ .number = 2.0 },
                        .right = &.{ .number = 0.5 },
                    } },
                } },
                .description = "Expand\n\nWe can rewrite $a * b$ as $b * c + b * d = bc + bd$, where $c$ is the whole part of $a$ and $d$ is the fractional part.",
                .substeps = &.{},
            },

            // step 2: simplify
            &.{
                .before = &.{ .binary = .{
                    .operation = .addition,
                    .left = &.{ .binary = .{
                        .operation = .multiplication,
                        .left = &.{ .number = 2.0 },
                        .right = &.{ .number = 1.0 },
                    } },
                    .right = &.{ .binary = .{
                        .operation = .multiplication,
                        .left = &.{ .number = 2.0 },
                        .right = &.{ .number = 0.5 },
                    } },
                } },
                .after = &.{ .binary = .{
                    .operation = .addition,
                    .left = &.{ .number = 2.0 },
                    .right = &.{ .number = 1.0 },
                } },
                .description = "Simplify",
                .substeps = @constCast(&[_]*const Step(f64){
                    // [bc] + bd
                    &.{
                        .before = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = 2.0 },
                            .right = &.{ .number = 1.0 },
                        } },
                        .after = &.{ .number = 2 },
                        .description = "Multiply 2 by 1",
                        .substeps = &.{},
                    },
                    // bc + [bd]
                    &.{
                        .before = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = 2.0 },
                            .right = &.{ .number = 0.5 },
                        } },
                        .after = &.{ .number = 1 },
                        .description = "Multiply 2 by 0.5",
                        .substeps = @constCast(&[_]*const Step(f64){
                            &.{
                                .before = &.{ .binary = .{
                                    .operation = .multiplication,
                                    .left = &.{ .number = 5.0 },
                                    .right = &.{ .number = 2.0 },
                                } },
                                .after = &.{ .number = 10.0 },
                                .description = "Multiply the fractional part of 0.5 (as if it was an integer) with 2",
                                .substeps = &.{},
                            },
                            &.{
                                .before = &.{ .number = 10.0 },
                                .after = &.{ .number = 1.0 },
                                .description = "Move the decimal point left by 1 place(-s)",
                                .substeps = &.{},
                            },
                        }),
                    },
                }),
            },

            // step 3: add
            &.{
                .before = &.{ .binary = .{
                    .operation = .addition,
                    .left = &.{ .number = 2.0 },
                    .right = &.{ .number = 1.0 },
                } },
                .after = &.{ .number = 3.0 },
                .description = "Add 2 and 1 together",
                .substeps = &.{},
            },
        }),
    };

    try testing.expectEqualDeep(expected, solution);
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
