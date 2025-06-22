pub const Key = enum {
    a,
    b,
};

pub fn divFloor(comptime T: type) Template(Key, T) {
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
            _ = expression;
            const I = @Type(.{ .int = .{ .bits = @bitSizeOf(T), .signedness = .signed } });

            const a: I = @intFromFloat(bindings.get(.a).?.number);
            const b: I = @intFromFloat(bindings.get(.b).?.number);

            var steps = std.ArrayList(*const Step(T)).init(allocator);

            var magnitude_steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, @as(usize, @intFromFloat(@ceil(@log10(bindings.get(.a).?.number)))) + 1);

            // MARK: magnitude
            var x: I = 1;
            while (b * x <= a) : (x *= 10) {
                try magnitude_steps.append(try (Step(T){
                    .before = try (Expression(T){ .binary = .{
                        .left = bindings.get(.b).?,
                        .right = &.{ .number = @floatFromInt(x) },
                        .operation = .multiplication,
                    } }).clone(allocator),
                    .after = try (Expression(T){ .number = @floatFromInt(b * x) }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Since {d} is less than {d}, we add 1 decimal place to our multiplier", .{ b * x, a }),
                    .substeps = &.{},
                }).clone(allocator));
            }

            try magnitude_steps.append(try (Step(T){
                .before = try (Expression(T){ .number = @floatFromInt(b * x) }).clone(allocator),
                .after = try (Expression(T){ .number = @as(T, @floatFromInt(b * x)) / 10.0 }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Since {d} is more than {d}, divide the multiplier by 10", .{ b * x, a }),
                .substeps = &.{},
            }).clone(allocator));

            x = @divExact(x, 10);
            var y: I = x;

            try steps.append(try (Step(T){
                .before = try (Expression(T){ .number = 1 }).clone(allocator),
                .after = try (Expression(T){ .number = @floatFromInt(x) }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Figure out the magnitude of the result", .{}),
                .substeps = try magnitude_steps.toOwnedSlice(),
            }).clone(allocator));

            var refine_steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, @as(usize, @intFromFloat(@ceil(@log10(bindings.get(.a).?.number)))) + 1);

            // MARK: refinement
            var i: I = 1;
            while (y != 1) {
                const before = x;

                var this_refine_steps = std.ArrayList(*const Step(T)).init(allocator);

                while (b * (x + y * i) <= a) : (i += 1) {
                    try this_refine_steps.append(try (Step(T){
                        .before = try (Expression(T){
                            .binary = .{
                                .left = bindings.get(.b).?,
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
                        }).clone(allocator),
                        .after = try (Expression(T){ .number = @floatFromInt(b * (x + y * i)) }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Since {d} is less than {d}, we add one more magnitude to our multiplier", .{ b * (x + y * i), a }),
                        .substeps = &.{},
                    }).clone(allocator));
                }

                try this_refine_steps.append(try (Step(T){
                    .before = try (Expression(T){
                        .binary = .{
                            .left = bindings.get(.b).?,
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
                    }).clone(allocator),
                    .after = try (Expression(T){ .number = @floatFromInt(b * (x + y * i)) }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Since {d} is more than {d}, we go back to the previous multiplier and change the magnitude to {d}", .{ b * (x + y * i), a, @divExact(y, 10) }),
                    .substeps = &.{},
                }).clone(allocator));

                x += y * (i - 1);
                y = @divExact(y, 10);
                i = 1;

                try refine_steps.append(try (Step(T){
                    .before = try (Expression(T){ .number = @floatFromInt(before) }).clone(allocator),
                    .after = try (Expression(T){ .number = @floatFromInt(x) }).clone(allocator),
                    .description = try allocator.dupe(u8, "Refine the search"),
                    .substeps = try this_refine_steps.toOwnedSlice(),
                }).clone(allocator));
            }

            try steps.appendSlice(try refine_steps.toOwnedSlice());

            // MARK: digits
            while (b * (x + i) <= a) : (i += 1) {
                try refine_steps.append(try (Step(T){
                    .before = try (Expression(T){
                        .binary = .{
                            .left = bindings.get(.b).?,
                            .right = &.{ .function = .{
                                .name = "add",
                                .arguments = @constCast(&[_]*const Expression(T){
                                    &.{ .number = @floatFromInt(x) },
                                    &.{ .number = @floatFromInt(y) },
                                }),
                                .body = null,
                            } },
                            .operation = .multiplication,
                        },
                    }).clone(allocator),
                    .after = try (Expression(T){ .number = @floatFromInt(b * (x + i)) }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Since {d} is less than {d}, we add one more magnitude to our multiplier", .{ b * (x + i), a }),
                    .substeps = &.{},
                }).clone(allocator));
            }

            try refine_steps.append(try (Step(T){
                .before = try (Expression(T){
                    .binary = .{
                        .left = bindings.get(.b).?,
                        .right = &.{ .function = .{
                            .name = "add",
                            .arguments = @constCast(&[_]*const Expression(T){
                                &.{ .number = @floatFromInt(x) },
                                &.{ .binary = .{
                                    .left = &.{ .number = @floatFromInt(y) },
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
                }).clone(allocator),
                .after = try (Expression(T){ .number = @floatFromInt(b * (x + y * (i - 1))) }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Since {d} is more than {d}, we go back to the previous multiplier and since the magnitude is equal to 1, we found the answer.", .{ b * (x + y * i), a }),
                .substeps = &.{},
            }).clone(allocator));

            x += y * (i - 1);
            try steps.append(try (Step(T){
                .before = try steps.getLast().after.?.clone(allocator),
                .after = try (Expression(T){ .number = @floatFromInt(x) }).clone(allocator),
                .description = try allocator.dupe(u8, "Refine the search"),
                .substeps = try refine_steps.toOwnedSlice(),
            }).clone(allocator));

            return Solution(T){ .steps = try steps.toOwnedSlice() };
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

// TODO tests

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
