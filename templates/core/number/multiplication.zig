pub const Key = enum {
    a,
    b,
};

pub fn multiplication(comptime T: type) Template(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates(T).get("core/number/number");
            var bindings = Bindings(Key, T).init(.{});

            _ = try number.module.structure.matches(expression.binary.left);
            bindings.put(.a, expression.binary.left);

            _ = try number.module.structure.matches(expression.binary.right);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const is_a_integer = @rem(a, 1.0) == 0.0;
            const is_b_integer = @rem(b, 1.0) == 0.0;

            // MARK: a * b; a, b ∈ Z
            if (is_a_integer and is_b_integer) {
                const solution = try Solution(T).init(1, allocator);

                solution.steps[0] = try (Step(T){
                    .before = try expression.clone(allocator),
                    .after = try (Expression(T){ .number = a * b }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ a, b }),
                    .substeps = try allocator.alloc(*const Step(T), 0),
                }).clone(allocator);

                return solution;
            }

            // MARK: a * b; a ∈ Z or b ∈ Z
            if (is_a_integer or is_b_integer and !(is_a_integer and is_b_integer)) {
                var steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, 4);

                // Here, a is the floating-point number.
                // Let c be equal to the whole part of a and d be equal to the fractional part of a.
                // (c + d) * b = bc + bd <=> c + d = a
                const not_integer, const integer = if (is_a_integer) .{ b, a } else .{ a, b };

                const c = @divFloor(not_integer, 1.0);
                const d = @rem(not_integer, 1.0);

                try steps.append(try (Step(T){
                    .before = try expression.clone(allocator),
                    .after = try (Expression(T){ .binary = .{
                        .operation = .addition,
                        .left = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = integer },
                            .right = &.{ .number = c },
                        } },
                        .right = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = integer },
                            .right = &.{ .number = d },
                        } },
                    } }).clone(allocator),
                    .description = try allocator.dupe(u8, "Expand\n\nWe can rewrite $a * b$ as $b * c + b * d = bc + bd$, where $c$ is the whole part of $a$ and $d$ is the fractional part."),
                    .substeps = try allocator.alloc(*const Step(T), 0),
                }).clone(allocator));

                // simplify
                const bc = b * c;
                const bd = b * d;

                try steps.append(try (Step(T){
                    .before = try steps.items[0].after.?.clone(allocator),
                    .after = try (Expression(T){ .binary = .{
                        .operation = .addition,
                        .left = &.{ .number = bc },
                        .right = &.{ .number = bd },
                    } }).clone(allocator),

                    .description = try allocator.dupe(u8, "Simplify"),

                    .substeps = blk: {
                        const substeps = try allocator.alloc(*const Step(T), 2);

                        substeps[0] = try (Step(T){
                            .before = try (Expression(T){ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = b },
                                .right = &.{ .number = c },
                            } }).clone(allocator),
                            .after = try (Expression(T){ .number = bc }).clone(allocator),
                            .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ b, c }),
                            .substeps = try allocator.alloc(*const Step(T), 0),
                        }).clone(allocator);

                        substeps[1] = try (Step(T){
                            .before = try (Expression(T){ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = b },
                                .right = &.{ .number = d },
                            } }).clone(allocator),
                            .after = try (Expression(T){ .number = bd }).clone(allocator),
                            .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ b, d }),
                            .substeps = try allocator.alloc(*const Step(T), 0),
                        }).clone(allocator);

                        break :blk substeps;
                    },
                }).clone(allocator));

                // add
                const addition = template.Templates(T).get("core/number/addition");
                const new_bindings = Bindings(addition.key, T).init(.{
                    .a = steps.items[1].after.?.binary.left,
                    .b = steps.items[1].after.?.binary.right,
                });

                const addition_result = try addition.module.structure.solve(steps.items[1].after.?, new_bindings, allocator);
                defer allocator.free(addition_result.steps);

                for (addition_result.steps) |step| {
                    try steps.append(step);
                }

                return Solution(T){
                    .steps = try steps.toOwnedSlice(),
                };
            }

            // TODO float * float
            unreachable;
        }
    };

    return Template(Key, T){
        .structure = .{
            .name = "Number multiplication",
            .ast = Expression(T){
                .binary = .{
                    .operation = .multiplication,
                    .left = &Expression(T){ .templated = .number },
                    .right = &Expression(T){ .templated = .number },
                },
            },
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

test multiplication {
    const Multiplication = multiplication(f64);
    const two_minus_one = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 3.0 },
    } };

    try testing.expect(Multiplication.structure.ast.structural() == two_minus_one.structural());
}

test "multiplication(T).matches" {
    const Multiplication = multiplication(f64);

    const two_times_three = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 3.0 },
    } };
    const half_times_five = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 0.5 },
        .right = &.{ .number = 5.0 },
    } };

    var bindings = try Multiplication.structure.matches(&two_times_three);
    try testing.expectEqualDeep(bindings.get(.a), two_times_three.binary.left);
    try testing.expectEqualDeep(bindings.get(.b), two_times_three.binary.right);

    bindings = try Multiplication.structure.matches(&half_times_five);
    try testing.expectEqualDeep(bindings.get(.a), half_times_five.binary.left);
    try testing.expectEqualDeep(bindings.get(.b), half_times_five.binary.right);
}

test "multiplication(T).solve" {
    const Multiplication = multiplication(f64);

    const two_times_three = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 3.0 },
    } };

    const bindings = try Multiplication.structure.matches(&two_times_three);
    const solution = try Multiplication.structure.solve(&two_times_three, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .steps = @constCast(&[_]*const Step(f64){
            &.{
                .before = &two_times_three,
                .after = &.{ .number = 6.0 },
                .description = "Multiply 2 by 3",
                .substeps = &.{},
            },
        }),
    };

    try testing.expectEqualDeep(expected, solution);
}

test "multiplication(T).solve - a * b, a ∉ Z" {
    const Multiplication = multiplication(f64);

    const three_halves_times_two = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 1.5 },
        .right = &.{ .number = 2.0 },
    } };

    const bindings = try Multiplication.structure.matches(&three_halves_times_two);
    const solution = try Multiplication.structure.solve(&three_halves_times_two, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .steps = @constCast(&[_]*const Step(f64){
            // step 1: rewrite
            &.{
                .before = &three_halves_times_two,
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
                        .substeps = &.{},
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
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
