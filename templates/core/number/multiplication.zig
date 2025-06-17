pub const Key = enum {
    a,
    b,
};

pub fn multiplication(comptime T: type) Template(Key, T) {
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

        // generic solver
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            // Let c be equal to the whole part of a and d be equal to the fractional part of a.
            // Let e be equal to the whole part of b and f be equal to the fractional part of b.
            //
            // (c + d) * (e + f) = ce + cf + de + df <=> c + d = a and e + f = b
            var steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, 4);

            // c, d
            const c = @divFloor(a, 1.0);
            const d = @rem(a, 1.0);

            // e, f
            const e = @divFloor(b, 1.0);
            const f = @rem(b, 1.0);

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

                    // always integer * integer
                    substeps[0] = try (Step(T){
                        .before = try steps.items[0].after.?.binary.left.binary.left.binary.left.clone(allocator),
                        .after = try (Expression(T){ .number = ce }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ c, e }),
                        .substeps = try allocator.alloc(*const Step(T), 0),
                    }).clone(allocator);

                    // always integer * small float (x2)
                    const small_float_int = template.Templates.get(.@"core/number/multiplication/small float, int");

                    substeps[1] = try (Step(T){
                        .before = try steps.items[0].after.?.binary.left.binary.left.binary.right.clone(allocator),
                        .after = try (Expression(T){ .number = cf }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ c, f }),
                        .substeps = (try small_float_int(T).solve(
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
                        .substeps = (try small_float_int(T).solve(
                            steps.items[0].after.?.binary.left.binary.right,
                            Bindings(Key, T).init(.{
                                .a = steps.items[0].after.?.binary.left.binary.right.binary.left,
                                .b = steps.items[0].after.?.binary.left.binary.right.binary.right,
                            }),
                            allocator,
                        )).steps,
                    }).clone(allocator);

                    // always small float * small float
                    const small_floats = template.Templates.get(.@"core/number/multiplication/small float, small float");

                    substeps[3] = try (Step(T){
                        .before = try steps.items[0].after.?.binary.right.clone(allocator),
                        .after = try (Expression(T){ .number = df }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ d, f }),
                        .substeps = (try small_floats(T).solve(
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
            .variants = @constCast(&[_]Variant(Key, T){
                template.Templates.get(.@"core/number/multiplication/small float, small float")(T),
                template.Templates.get(.@"core/number/multiplication/small float, int")(T),
                template.Templates.get(.@"core/number/multiplication/float, int")(T),
                template.Templates.get(.@"core/number/multiplication/int, int")(T),
            }),
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

    _ = template.Templates.templates();
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

    const expression = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 4.5 },
        .right = &.{ .number = 1.5 },
    } };

    const bindings = try Multiplication.structure.matches(&expression);
    const solution = try Multiplication.structure.solve(&expression, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const stderr = std.io.getStdErr().writer();
    for (solution.steps, 0..) |step, i| {
        std.debug.print("#{d}. ", .{i + 1});
        try std.zon.stringify.serializeArbitraryDepth(step.before, .{ .whitespace = false }, stderr);
        std.debug.print(" -> ", .{});
        try std.zon.stringify.serializeArbitraryDepth(step.after.?, .{ .whitespace = false }, stderr);
        std.debug.print(" ('{s}')\n", .{step.description});

        for (step.substeps, 0..) |substep, j| {
            std.debug.print("\t#{d}.{d} ", .{ i + 1, j + 1 });
            try std.zon.stringify.serializeArbitraryDepth(substep.before, .{ .whitespace = false }, stderr);
            std.debug.print(" -> ", .{});
            try std.zon.stringify.serializeArbitraryDepth(substep.after.?, .{ .whitespace = false }, stderr);
            std.debug.print(" ('{s}')\n", .{substep.description});

            for (substep.substeps, 0..) |subsubstep, k| {
                std.debug.print("\t\t#{d}.{d}.{d} ", .{ i + 1, j + 1, k + 1 });
                try std.zon.stringify.serializeArbitraryDepth(subsubstep.before, .{ .whitespace = false }, stderr);
                std.debug.print(" -> ", .{});
                try std.zon.stringify.serializeArbitraryDepth(subsubstep.after.?, .{ .whitespace = false }, stderr);
                std.debug.print(" ('{s}')\n", .{subsubstep.description});
            }
        }
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
