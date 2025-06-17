pub const Key = enum {
    a,
    b,
};

pub fn multiplication(comptime T: type) Template(Key, T) {
    const variants = @constCast(&template.Templates.variants(.@"core/number/multiplication", T));

    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates.get(.@"core/number/number").module(T);
            var bindings = Bindings(Key, T).init(.{});

            _ = try number.structure.matches(expression.binary.left);
            bindings.put(.a, expression.binary.left);

            _ = try number.structure.matches(expression.binary.right);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            for (variants) |variant| {
                const new_bindings = variant.matches(expression) catch continue;

                return variant.solve(expression, new_bindings, allocator);
            }

            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            // Let c be equal to the whole part of a and d be equal to the fractional part of a.
            // Let e be equal to the whole part of b and f be equal to the fractional part of b.
            //
            // (c + d) * (e + f) = ce + cf + de + df <=> c + d = a and e + f = b
            var steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, 4);

            // c, d
            const c = @divFloor(a, 1.0);
            const d = @mod(a, 1.0);

            // e, f
            const e = @divFloor(b, 1.0);
            const f = @mod(b, 1.0);

            // expand
            try steps.append(try (Step(T){
                .before = try expression.clone(allocator),

                // ce + cf + de + df
                .after = try (Expression(T){
                    .binary = .{
                        .operation = .addition,
                        // ce + cf + de
                        .left = &.{
                            .binary = .{
                                .operation = .addition,
                                // ce + cf
                                .left = &.{
                                    .binary = .{
                                        .operation = .addition,
                                        // ce
                                        .left = &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = c },
                                            .right = &.{ .number = e },
                                        } },

                                        // cf
                                        .right = &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = c },
                                            .right = &.{ .number = f },
                                        } },
                                    },
                                },

                                // de
                                .right = &.{ .binary = .{
                                    .operation = .multiplication,
                                    .left = &.{ .number = d },
                                    .right = &.{ .number = e },
                                } },
                            },
                        },

                        // df
                        .right = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = d },
                            .right = &.{ .number = f },
                        } },
                    },
                }).clone(allocator),

                .description = try allocator.dupe(u8,
                    \\Expand
                    \\
                    \\We can rewrite $a$ as $c + d$, where $c$ is the whole part of $a$ and $d$ is the fractional part.
                    \\We can also rewrite $b$ as $e + f$, where $e$ is the whole part of $b$ and $f$ is the fractional part.
                    \\This gives us $a * b = (c + d) * (e + f) = ce + cf + de + df$.
                ),

                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator));

            // simplify
            const ce = c * e;
            const cf = c * f;
            const de = d * e;
            const df = d * f;

            try steps.append(try (Step(T){
                .before = try steps.items[0].after.?.clone(allocator),
                .after = try (Expression(T){ .binary = .{
                    .operation = .addition,
                    .left = &.{ .binary = .{
                        .operation = .addition,
                        .left = &.{ .binary = .{
                            .operation = .addition,
                            .left = &.{ .number = ce },
                            .right = &.{ .number = cf },
                        } },
                        .right = &.{ .number = de },
                    } },
                    .right = &.{ .number = df },
                } }).clone(allocator),

                .description = try allocator.dupe(u8, "Simplify"),

                .substeps = blk: {
                    var substeps = try allocator.alloc(*const Step(T), 4);

                    // always integer * integer, always one step
                    const solution_one = try solve(
                        steps.items[0].after.?.binary.left.binary.left.binary.left,
                        Bindings(Key, T).init(.{
                            .a = steps.items[0].after.?.binary.left.binary.left.binary.left.binary.right,
                            .b = steps.items[0].after.?.binary.left.binary.left.binary.left.binary.left,
                        }),
                        allocator,
                    );
                    substeps[0] = solution_one.steps[0];
                    defer allocator.free(solution_one.steps);

                    // always integer * small float (x2)
                    substeps[1] = try (Step(T){
                        .before = try steps.items[0].after.?.binary.left.binary.left.binary.right.clone(allocator),
                        .after = try (Expression(T){ .number = cf }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ c, f }),
                        .substeps = (try solve(
                            steps.items[0].after.?.binary.left.binary.left.binary.right,
                            Bindings(Key, T).init(.{
                                .a = steps.items[0].after.?.binary.left.binary.left.binary.right.binary.right,
                                .b = steps.items[0].after.?.binary.left.binary.left.binary.right.binary.left,
                            }),
                            allocator,
                        )).steps,
                    }).clone(allocator);

                    substeps[2] = try (Step(T){
                        .before = try steps.items[0].after.?.binary.left.binary.right.clone(allocator),
                        .after = try (Expression(T){ .number = de }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ d, e }),
                        .substeps = (try solve(
                            steps.items[0].after.?.binary.left.binary.right,
                            Bindings(Key, T).init(.{
                                .a = steps.items[0].after.?.binary.left.binary.right.binary.left,
                                .b = steps.items[0].after.?.binary.left.binary.right.binary.right,
                            }),
                            allocator,
                        )).steps,
                    }).clone(allocator);

                    // always non-zero/one small float * non-zero/one small float
                    substeps[3] = try (Step(T){
                        .before = try steps.items[0].after.?.binary.right.clone(allocator),
                        .after = try (Expression(T){ .number = df }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ d, f }),
                        .substeps = (try solve(
                            steps.items[0].after.?.binary.right,
                            Bindings(Key, T).init(.{
                                .a = steps.items[0].after.?.binary.right.binary.left,
                                .b = steps.items[0].after.?.binary.right.binary.right,
                            }),
                            allocator,
                        )).steps,
                    }).clone(allocator);

                    break :blk substeps;
                },
            }).clone(allocator));

            // add
            try steps.append(try (Step(T){
                .before = try steps.items[1].after.?.clone(allocator),
                .after = try (Expression(T){ .number = ce + cf + de + df }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Add {d}, {d}, {d} and {d} together", .{ ce, cf, de, df }),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator));

            return Solution(T){ .steps = try steps.toOwnedSlice() };
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
            .variants = variants,
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

    try testing.expect((comptime Multiplication.structure.ast.structural()) == two_minus_one.structural());
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
    inline for (.{ f16, f32, f64 }) |T| {
        const Multiplication = multiplication(T);

        const expression = Expression(T){ .binary = .{
            .operation = .multiplication,
            .left = &.{ .number = 4.5 },
            .right = &.{ .number = 1.5 },
        } };

        const bindings = try Multiplication.structure.matches(&expression);
        const solution = try Multiplication.structure.solve(&expression, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = &.{
                        .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = 4.5 },
                            .right = &.{ .number = 1.5 },
                        },
                    },
                    .after = &.{ .binary = .{
                        .operation = .addition,
                        .left = &.{
                            .binary = .{
                                .operation = .addition,
                                .left = &.{
                                    .binary = .{
                                        .operation = .addition,
                                        .left = &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = 4.0 },
                                            .right = &.{ .number = 1.0 },
                                        } },
                                        .right = &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = 4.0 },
                                            .right = &.{ .number = 0.5 },
                                        } },
                                    },
                                },
                                .right = &.{ .binary = .{
                                    .operation = .multiplication,
                                    .left = &.{ .number = 0.5 },
                                    .right = &.{ .number = 1.0 },
                                } },
                            },
                        },
                        .right = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = 0.5 },
                            .right = &.{ .number = 0.5 },
                        } },
                    } },
                    .description = "Expand\n\nWe can rewrite $a$ as $c + d$, where $c$ is the whole part of $a$ and $d$ is the fractional part.\nWe can also rewrite $b$ as $e + f$, where $e$ is the whole part of $b$ and $f$ is the fractional part.\nThis gives us $a * b = (c + d) * (e + f) = ce + cf + de + df$.",
                    .substeps = &.{},
                },
                &.{
                    .before = &.{ .binary = .{
                        .operation = .addition,
                        .left = &.{ .binary = .{
                            .operation = .addition,
                            .left = &.{ .binary = .{
                                .operation = .addition,
                                .left = &.{ .binary = .{
                                    .operation = .multiplication,
                                    .left = &.{ .number = 4.0 },
                                    .right = &.{ .number = 1.0 },
                                } },
                                .right = &.{ .binary = .{
                                    .operation = .multiplication,
                                    .left = &.{ .number = 4.0 },
                                    .right = &.{ .number = 0.5 },
                                } },
                            } },
                            .right = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 0.5 },
                                .right = &.{ .number = 1 },
                            } },
                        } },
                        .right = &.{ .binary = .{
                            .operation = .multiplication,
                            .left = &.{ .number = 0.5 },
                            .right = &.{ .number = 0.5 },
                        } },
                    } },
                    .after = &.{ .binary = .{
                        .operation = .addition,
                        .left = &.{ .binary = .{
                            .operation = .addition,
                            .left = &.{ .binary = .{
                                .operation = .addition,
                                .left = &.{ .number = 4 },
                                .right = &.{ .number = 2 },
                            } },
                            .right = &.{ .number = 0.5 },
                        } },
                        .right = &.{ .number = 0.25 },
                    } },
                    .description = "Simplify",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 4.0 },
                                .right = &.{ .number = 1.0 },
                            } },
                            .after = &.{ .number = 4.0 },
                            .description = "Anything multiplied by 1 is equal to itself",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 4.0 },
                                .right = &.{ .number = 0.5 },
                            } },
                            .after = &.{ .number = 2.0 },
                            .description = "Multiply 4 by 0.5",
                            .substeps = @constCast(&[_]*const Step(T){
                                &.{
                                    .before = &.{ .binary = .{
                                        .operation = .multiplication,
                                        .left = &.{ .number = 4.0 },
                                        .right = &.{ .number = 0.5 },
                                    } },
                                    .after = &.{ .number = 20.0 },
                                    .description = "Multiply the fractional part of 0.5 (as if it was an integer - 5) with 4",
                                    .substeps = &.{},
                                },
                                &.{
                                    .before = &.{ .number = 20.0 },
                                    .after = &.{ .number = 2.0 },
                                    .description = "Move the decimal point left by 1 place(-s)",
                                    .substeps = &.{},
                                },
                            }),
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 0.5 },
                                .right = &.{ .number = 1.0 },
                            } },
                            .after = &.{ .number = 0.5 },
                            .description = "Multiply 0.5 by 1",
                            .substeps = @constCast(&[_]*const Step(T){
                                &.{
                                    .before = &.{ .binary = .{
                                        .operation = .multiplication,
                                        .left = &.{ .number = 0.5 },
                                        .right = &.{ .number = 1 },
                                    } },
                                    .after = &.{ .number = 0.5 },
                                    .description = "Anything multiplied by 1 is equal to itself",
                                    .substeps = &.{},
                                },
                            }),
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 0.5 },
                                .right = &.{ .number = 0.5 },
                            } },
                            .after = &.{ .number = 0.25 },
                            .description = "Multiply 0.5 by 0.5",
                            .substeps = @constCast(&[_]*const Step(T){
                                &.{
                                    .before = &.{ .binary = .{
                                        .operation = .multiplication,
                                        .left = &.{ .number = 0.5 },
                                        .right = &.{ .number = 0.5 },
                                    } },
                                    .after = &.{ .number = 25 },
                                    .description = "Multiply the fractional parts of 0.5 and 0.5 (5 and 5) as if they were integers",
                                    .substeps = &.{},
                                },
                                &.{
                                    .before = &.{ .number = 25 },
                                    .after = &.{ .number = 0.25 },
                                    .description = "Make the result have 2 decimal places",
                                    .substeps = &.{},
                                },
                            }),
                        },
                    }),
                },
                &.{
                    .before = &.{ .binary = .{
                        .operation = .addition,
                        .left = &.{ .binary = .{
                            .operation = .addition,
                            .left = &.{ .binary = .{
                                .operation = .addition,
                                .left = &.{ .number = 4.0 },
                                .right = &.{ .number = 2.0 },
                            } },
                            .right = &.{ .number = 0.5 },
                        } },
                        .right = &.{ .number = 0.25 },
                    } },
                    .after = &.{ .number = 6.75 },
                    .description = "Add 4, 2, 0.5 and 0.25 together",
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
