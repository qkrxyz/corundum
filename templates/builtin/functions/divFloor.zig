pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "7393 / 23",
            &Expression(T){ .function = .{
                .name = "divFloor",
                .arguments = @constCast(&[_]*const Expression(T){
                    &.{ .number = 7393 },
                    &.{ .number = 23 },
                }),
                .body = null,
            } },
        },
    });
}

pub const Key = enum {
    a,
    b,
};

pub fn divFloor(comptime T: type) Template(Key, T) {
    const variants = template.Templates.variants(.@"builtin/functions/divFloor", T);

    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.function.arguments[0]);
            bindings.put(.b, expression.function.arguments[1]);

            return bindings;
        }

        // MARK: .solve()
        // How many times does `a` fit in `b`?
        // We can do this:
        //
        // Before everything, we have some conditions to check:
        // - If `a` < `b`, return 0.
        // - If `a` or `b` is negative, make both positive and set a flag that we need to change the sign of the result.
        //
        // Let's define our multiplier as `x = 1`.
        // At first, multiply x by 10, as long as `b * x <= a`.
        // When `b * x > a`, divide `x` by 10, define `y` as `y = x` and `i` as `i = 1`.
        //
        // As long as y is not equal to one, do the following:
        // Start incrementing i as long as `b * (x + y * i) <= a`; after that
        // `x += (y * (i - 1))`, divide `y` by 10 and set `i` to 1.
        //
        // After that, do the same as the inner loop from the step above:
        // As long as `b * (x + i) <= a`, increment `i` by one.
        // Lastly, add `y * (i - 1)` to `x`.
        // `x` is your result.
        //
        // Compared to the usual "bring digits down until it fits", you can very quickly approximate this
        // (e.g. on the side or even in your head) by looking at the lengths of a and b, and only then actually writing something down.
        //
        // e.g. for 7393/23, b (and the multiplier) would take this journey:
        // - 23, 230, 2300, 23000, 2300   | 1, 10, 100, 1000, 100
        // - 2300, 4600, 6900, 9200, 6900 | 100, 200, 300, 400, 300
        // - 6900, 7130, 7360, 7590, 7360 | 300, 310, 320, 330, 320
        // - 7360, 7383, 7406, 7383       | 320, 321, 322, 321
        // Since we can't increment the multiplier by a value lower than 1, we have our result.
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            for (variants) |variant| {
                const new_bindings = variant.matches(expression) catch continue;

                return variant.solve(expression, new_bindings, allocator);
            }

            const I = @Type(.{ .int = .{ .bits = @bitSizeOf(T), .signedness = .signed } });

            const a_float: T = @abs(bindings.get(.a).?.number);
            const a: I = @intFromFloat(a_float);
            const b_float: T = @abs(bindings.get(.b).?.number);
            const b: I = @intFromFloat(b_float);

            const solution = try Solution(T).init(
                blk: {
                    var length: usize = 1;
                    var x: I = 1;

                    while (b * x <= a) : ({
                        x *= 10;
                        length += 1;
                    }) {}

                    break :blk length;
                },
                true,
                allocator,
            );

            // MARK: magnitude
            var magnitude = try std.ArrayList(*const Step(T)).initCapacity(
                allocator,
                solution.steps.len,
            );

            var x: I = 1;
            while (b * x <= a) : (x *= 10) {
                const step = try Step(T).init(
                    try Expression(T).init(.{ .binary = .{
                        .left = &.{ .number = b_float },
                        .right = &.{ .number = @floatFromInt(x) },
                        .operation = .multiplication,
                    } }, allocator),
                    try Expression(T).init(.{ .number = @floatFromInt(b * x) }, allocator),
                    try std.fmt.allocPrint(allocator, "Since {d} is less than or equal to {d}, we add 1 decimal place to our multiplier", .{ b * x, a }),
                    &.{},
                    allocator,
                );

                try magnitude.append(step);
            }

            try magnitude.append(try Step(T).init(
                try Expression(T).init(.{ .binary = .{
                    .left = &.{ .number = b_float },
                    .right = &.{ .number = @floatFromInt(x) },
                    .operation = .multiplication,
                } }, allocator),
                try Expression(T).init(.{ .number = @as(T, @floatFromInt(b * x)) / 10.0 }, allocator),
                try std.fmt.allocPrint(allocator, "Since {d} is more than {d}, divide the multiplier by 10", .{ b * x, a }),
                &.{},
                allocator,
            ));

            x = @divExact(x, 10);
            var y: I = x;

            const magnitude_slice = try magnitude.toOwnedSlice();
            solution.steps[0] = try Step(T).init(
                try Expression(T).init(.{ .number = 1 }, allocator),
                try Expression(T).init(.{ .number = @floatFromInt(x) }, allocator),
                try std.fmt.allocPrint(allocator, "Figure out the magnitude of the result", .{}),
                magnitude_slice,
                allocator,
            );

            // MARK: refinement
            var refine = try std.ArrayList(*const Step(T)).initCapacity(
                allocator,
                solution.steps.len,
            );

            var i: I = 1;
            while (y != 1) {
                var subrefine = try std.ArrayList(*const Step(T)).initCapacity(
                    allocator,
                    blk: {
                        var result: I = 1;
                        while (b * (x + y * result) <= a) : (result += 1) {}
                        break :blk @intCast(result);
                    },
                );

                const x_float: T = @floatFromInt(x);
                const y_float: T = @floatFromInt(y);

                while (b * (x + y * i) <= a) : (i += 1) {
                    const step = try Step(T).init(
                        try Expression(T).init(.{
                            .binary = .{
                                .left = &.{ .number = b_float },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = x_float },
                                        &.{ .binary = .{
                                            .left = &.{ .number = y_float },
                                            .right = &.{ .number = @floatFromInt(i + 1) },
                                            .operation = .multiplication,
                                        } },
                                    }),
                                    .body = null,
                                } },
                                .operation = .multiplication,
                            },
                        }, allocator),
                        try Expression(T).init(.{ .number = @floatFromInt(b * (x + y * i)) }, allocator),
                        try std.fmt.allocPrint(allocator, "Since {d} is less than or equal to {d}, we add one more magnitude to our multiplier", .{ b * (x + y * i), a }),
                        &.{},
                        allocator,
                    );

                    try subrefine.append(step);
                }

                try subrefine.append(try Step(T).init(
                    try Expression(T).init(.{
                        .binary = .{
                            .left = &.{ .number = @floatFromInt(b) },
                            .right = &.{ .function = .{
                                .name = "add",
                                .arguments = @constCast(&[_]*const Expression(T){
                                    &.{ .number = @floatFromInt(x) },
                                    &.{ .binary = .{
                                        .left = &.{ .number = @floatFromInt(y) },
                                        .right = &.{ .number = @floatFromInt(i + 1) },
                                        .operation = .multiplication,
                                    } },
                                }),
                                .body = null,
                            } },
                            .operation = .multiplication,
                        },
                    }, allocator),
                    try Expression(T).init(.{ .number = @floatFromInt(b * (x + y * i)) }, allocator),
                    try std.fmt.allocPrint(allocator, "Since {d} is more than {d}, we go back to the previous multiplier and change the magnitude to {d}", .{ b * (x + y * i), a, @divExact(y, 10) }),
                    &.{},
                    allocator,
                ));

                x += y * (i - 1);
                y = @divExact(y, 10);
                i = 1;

                try refine.append(try Step(T).init(
                    try Expression(T).init(.{ .number = x_float }, allocator),
                    try Expression(T).init(.{ .number = @floatFromInt(x) }, allocator),
                    try allocator.dupe(u8, "Refine the search"),
                    try subrefine.toOwnedSlice(),
                    allocator,
                ));
            }

            @memcpy(solution.steps[1 .. 1 + refine.items.len], refine.items);
            defer refine.deinit();

            // MARK: digits
            var digit = try std.ArrayList(*const Step(T)).initCapacity(
                allocator,
                blk: {
                    var result: I = 1;
                    while (b * (x + result) <= a) : (result += 1) {}
                    break :blk @intCast(result);
                },
            );

            const y_float: T = @floatFromInt(y);
            while (b * (x + i) <= a) : (i += 1) {
                const step = try Step(T).init(
                    try Expression(T).init(.{
                        .binary = .{
                            .left = &.{ .number = b_float },
                            .right = &.{ .function = .{
                                .name = "add",
                                .arguments = @constCast(&[_]*const Expression(T){
                                    &.{ .number = @floatFromInt(x) },
                                    &.{ .number = @floatFromInt(i) },
                                }),
                                .body = null,
                            } },
                            .operation = .multiplication,
                        },
                    }, allocator),
                    try Expression(T).init(.{ .number = @floatFromInt(b * (x + i)) }, allocator),
                    try std.fmt.allocPrint(allocator, "Since {d} is less than or equal to {d}, we add one more magnitude to our multiplier", .{ b * (x + i), a }),
                    &.{},
                    allocator,
                );

                try digit.append(step);
            }

            try digit.append(try Step(T).init(
                try Expression(T).init(.{
                    .binary = .{
                        .left = &.{ .number = @floatFromInt(b) },
                        .right = &.{ .function = .{
                            .name = "add",
                            .arguments = @constCast(&[_]*const Expression(T){
                                &.{ .number = @floatFromInt(x) },
                                &.{ .binary = .{
                                    .left = &.{ .number = y_float },
                                    .right = &.{ .binary = .{
                                        .left = &.{ .number = @floatFromInt(i) },
                                        .right = &.{ .number = 1.0 },
                                        .operation = .subtraction,
                                    } },
                                    .operation = .multiplication,
                                } },
                            }),
                            .body = null,
                        } },
                        .operation = .multiplication,
                    },
                }, allocator),
                try Expression(T).init(.{ .number = @floatFromInt(b * (x + y * (i - 1))) }, allocator),
                try std.fmt.allocPrint(allocator, "Since {d} is more than {d}, we go back to the previous multiplier and since the magnitude is equal to 1, we found the answer.", .{ b * (x + y * i), a }),
                &.{},
                allocator,
            ));

            x += y * (i - 1);

            solution.steps[solution.steps.len - 1] = try Step(T).init(
                try solution.steps[solution.steps.len - 2].after.clone(allocator),
                try Expression(T).init(.{ .number = @floatFromInt(x) }, allocator),
                try allocator.dupe(u8, "Refine the search"),
                try digit.toOwnedSlice(),
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){ .structure = .{
        .name = "Builtin function: number division, rounded down",
        .ast = Expression(T){
            .function = .{
                .name = "divFloor",
                .arguments = @constCast(&[_]*const Expression(T){
                    &.{ .templated = .number },
                    &.{ .templated = .number },
                }),
                .body = null,
            },
        },
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

// MARK: tests
test divFloor {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = divFloor(T);

        const function = Expression(T){
            .function = .{
                .name = "divFloor",
                .arguments = @constCast(&[_]*const Expression(T){
                    &.{ .number = 42.0 },
                    &.{ .number = 3.0 },
                }),
                .body = null,
            },
        };

        const bindings = try Division.structure.matches(&function);

        try testing.expectEqualDeep(Bindings(Key, T).init(.{
            .a = &.{ .number = 42.0 },
            .b = &.{ .number = 3.0 },
        }), bindings);
    }
}

test "divFloor(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = divFloor(T);

        const function = testingData(T).get("7393 / 23").?;

        const bindings = try Division.structure.matches(function);
        const solution = try Division.structure.solve(function, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = &.{ .number = 1.0 },
                    .after = &.{ .number = 100.0 },
                    .description = "Figure out the magnitude of the result",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .binary = .{
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .number = 1.0 },
                                .operation = .multiplication,
                            } },
                            .after = &.{ .number = 23.0 },
                            .description = "Since 23 is less than or equal to 7393, we add 1 decimal place to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .number = 10.0 },
                                .operation = .multiplication,
                            } },
                            .after = &.{ .number = 230.0 },
                            .description = "Since 230 is less than or equal to 7393, we add 1 decimal place to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .number = 100.0 },
                                .operation = .multiplication,
                            } },
                            .after = &.{ .number = 2300.0 },
                            .description = "Since 2300 is less than or equal to 7393, we add 1 decimal place to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .number = 1000.0 },
                                .operation = .multiplication,
                            } },
                            .after = &.{ .number = 2300.0 },
                            .description = "Since 23000 is more than 7393, divide the multiplier by 10",
                            .substeps = &.{},
                        },
                    }),
                },
                &.{
                    .before = &.{ .number = 100.0 },
                    .after = &.{ .number = 300.0 },
                    .description = "Refine the search",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 100.0 }, &.{
                                            .binary = .{
                                                .operation = .multiplication,
                                                .left = &.{ .number = 100.0 },
                                                .right = &.{ .number = 2.0 },
                                            },
                                        },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 4600.0 },
                            .description = "Since 4600 is less than or equal to 7393, we add one more magnitude to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 100.0 }, &.{
                                            .binary = .{
                                                .operation = .multiplication,
                                                .left = &.{ .number = 100.0 },
                                                .right = &.{ .number = 3.0 },
                                            },
                                        },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 6900.0 },
                            .description = "Since 6900 is less than or equal to 7393, we add one more magnitude to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 100.0 }, &.{
                                            .binary = .{
                                                .operation = .multiplication,
                                                .left = &.{ .number = 100.0 },
                                                .right = &.{ .number = 4.0 },
                                            },
                                        },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 9200.0 },
                            .description = "Since 9200 is more than 7393, we go back to the previous multiplier and change the magnitude to 10",
                            .substeps = &.{},
                        },
                    }),
                },
                &.{
                    .before = &.{ .number = 300.0 },
                    .after = &.{ .number = 320.0 },
                    .description = "Refine the search",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 300.0 }, &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = 10.0 },
                                            .right = &.{ .number = 2.0 },
                                        } },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 7130.0 },
                            .description = "Since 7130 is less than or equal to 7393, we add one more magnitude to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 300.0 }, &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = 10.0 },
                                            .right = &.{ .number = 3.0 },
                                        } },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 7360.0 },
                            .description = "Since 7360 is less than or equal to 7393, we add one more magnitude to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 300.0 }, &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = 10.0 },
                                            .right = &.{ .number = 4.0 },
                                        } },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 7590.0 },
                            .description = "Since 7590 is more than 7393, we go back to the previous multiplier and change the magnitude to 1",
                            .substeps = &.{},
                        },
                    }),
                },
                &.{
                    .before = &.{ .number = 320.0 },
                    .after = &.{ .number = 321.0 },
                    .description = "Refine the search",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 320.0 },
                                        &.{ .number = 1.0 },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 7383.0 },
                            .description = "Since 7383 is less than or equal to 7393, we add one more magnitude to our multiplier",
                            .substeps = &.{},
                        },
                        &.{
                            .before = &.{ .binary = .{
                                .operation = .multiplication,
                                .left = &.{ .number = 23.0 },
                                .right = &.{ .function = .{
                                    .name = "add",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = 320.0 }, &.{ .binary = .{
                                            .operation = .multiplication,
                                            .left = &.{ .number = 1.0 },
                                            .right = &.{ .binary = .{
                                                .operation = .subtraction,
                                                .left = &.{ .number = 2.0 },
                                                .right = &.{ .number = 1.0 },
                                            } },
                                        } },
                                    }),
                                    .body = null,
                                } },
                            } },
                            .after = &.{ .number = 7383.0 },
                            .description = "Since 7406 is more than 7393, we go back to the previous multiplier and since the magnitude is equal to 1, we found the answer.",
                            .substeps = &.{},
                        },
                    }),
                },
            }),
        };

        try testing.expectEqualDeep(expected, solution);
    }
}

// TODO tests for a < b, a == b and negative inputs

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
