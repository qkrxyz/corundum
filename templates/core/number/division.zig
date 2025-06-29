pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "10 / 4", &Expression(T){
                .binary = .{
                    .left = &.{ .number = 10.0 },
                    .right = &.{ .number = 4.0 },
                    .operation = .division,
                },
            },
        },
        .{
            "323 / 160", &Expression(T){
                .binary = .{
                    .left = &.{ .number = 323.0 },
                    .right = &.{ .number = 160.0 },
                    .operation = .division,
                },
            },
        },
        .{
            "999 / 37", &Expression(T){
                .binary = .{
                    .left = &.{ .number = 999.0 },
                    .right = &.{ .number = 37.0 },
                    .operation = .division,
                },
            },
        },
    });
}

pub const Key = enum {
    a,
    b,
};

pub fn division(comptime T: type) Template(Key, T) {
    const variants = @constCast(&template.Templates.variants(.@"core/number/division", T));

    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.binary.left);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            const I = @Type(.{ .int = .{ .bits = @bitSizeOf(T), .signedness = .signed } });

            inline for (template.Templates.contains("core/identities/division")) |kind| {
                const resolved = template.Templates.resolve(kind, T);

                switch (resolved) {
                    .dynamic => |dynamic| {
                        const new_bindings = if (@typeInfo(@TypeOf(dynamic.matches)).@"fn".params.len == 2) dynamic.matches(expression, allocator) else dynamic.matches(expression);

                        if (new_bindings) |b| return dynamic.solve(expression, b, allocator) else |_| {}
                    },
                    .structure => |structure| {
                        if (structure.matches(expression)) |b| {
                            return structure.solve(expression, b, allocator);
                        } else |_| {}
                    },
                    // this is a structural template
                    .identity => unreachable,
                }
            }

            for (variants) |variant| {
                const new_bindings = variant.matches(expression) catch continue;

                return variant.solve(expression, new_bindings, allocator);
            }

            // guaranteed to be integers
            const a: I = @intFromFloat(bindings.get(.a).?.number);
            const b: I = @intFromFloat(bindings.get(.b).?.number);

            const solution = try Solution(T).init(3, true, allocator);

            // MARK: integer part
            const divFloor = template.Templates.get(.@"builtin/functions/divFloor");
            const new_bindings = Bindings(divFloor.key, T).init(.{
                .a = bindings.get(.a).?,
                .b = bindings.get(.b).?,
            });

            const div_floor_expression = Expression(T){ .function = .{
                .name = "divFloor",
                .arguments = @constCast(&[_]*const Expression(T){
                    new_bindings.get(.a).?,
                    new_bindings.get(.b).?,
                }),
                .body = null,
            } };

            const div_floor_solution = try divFloor.module(T).structure.solve(&div_floor_expression, new_bindings, allocator);

            solution.steps[0] = try Step(T).init(
                try div_floor_expression.clone(allocator),
                try div_floor_solution.steps[div_floor_solution.steps.len - 1].after.clone(allocator),
                try std.fmt.allocPrint(allocator, "Figure out how many times {d} fits in {d}", .{ b, a }),
                div_floor_solution.steps,
                allocator,
            );

            // MARK: remainder
            var remainder: I = @intCast(@abs(a - (@as(I, @intFromFloat(solution.steps[0].after.number)) * b)));
            const b_abs: I = @intCast(@abs(b));

            solution.steps[1] = try Step(T).init(
                try (Expression(T){
                    .function = .{
                        .name = "abs",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{
                                .function = .{
                                    .name = "sub",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        bindings.get(.a).?,
                                        &.{ .binary = .{
                                            .left = &.{ .number = solution.steps[0].after.number },
                                            .right = bindings.get(.b).?,
                                            .operation = .multiplication,
                                        } },
                                    }),
                                    .body = null,
                                },
                            },
                        }),
                        .body = null,
                    },
                }).clone(allocator),
                try (Expression(T){ .number = @floatFromInt(remainder) }).clone(allocator),
                try allocator.dupe(u8, "Calculate the remainder"),
                &.{},
                allocator,
            );

            // MARK: decimal part
            const upper_bound: usize = comptime @intFromFloat(@ceil(std.math.floatMantissaBits(T) * @log10(2.0)));
            var i: usize = 0;

            var substeps = try std.ArrayList(*const Step(T)).initCapacity(allocator, upper_bound + 1);
            var decimal: T = 0.0;

            while (remainder != 0 and i < upper_bound) : (i += 1) {
                var trailing_zeroes: usize = 0;

                var trailing_steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, blk: {
                    var j: usize = 0;
                    var x = remainder;

                    while (x < b_abs) {
                        x *= 10;
                        j += 1;
                    }

                    break :blk j;
                });

                // `trailing_zeroes` will always be at least 1, since `a < b` is guaranteed. later, it will be decreased by 1.
                while (remainder < b_abs) {
                    remainder *= 10;
                    trailing_zeroes += 1;

                    const step = try Step(T).init(
                        try (Expression(T){ .number = @floatFromInt(@divExact(remainder, 10)) }).clone(allocator),
                        try (Expression(T){ .number = @floatFromInt(remainder) }).clone(allocator),
                        try std.fmt.allocPrint(allocator, "Since {d} is smaller than {d}, multiply the remainder by 10 and add shift the decimal of the result of this step by {d} place(-s)", .{ @divExact(remainder, 10), b_abs, trailing_zeroes }),
                        &.{},
                        allocator,
                    );
                    try trailing_steps.append(step);
                }

                // digit
                const digit = @divFloor(remainder, b_abs);

                const digit_solution = try divFloor.module(T).structure.solve(
                    &Expression(T){
                        .function = .{
                            .name = "divFloor",
                            .arguments = @constCast(&[_]*const Expression(T){
                                &.{ .number = @floatFromInt(remainder) },
                                &.{ .number = @floatFromInt(b_abs) },
                            }),
                            .body = null,
                        },
                    },
                    Bindings(divFloor.key, T).init(.{
                        .a = &.{ .number = @floatFromInt(remainder) },
                        .b = &.{ .number = @floatFromInt(b_abs) },
                    }),
                    allocator,
                );

                const b_float: T = @floatFromInt(b_abs);
                const remainder_float: T = @floatFromInt(remainder);

                var trailing_substeps = try allocator.alloc(*const Step(T), digit_solution.steps.len + 1);

                @memcpy(trailing_substeps[0..digit_solution.steps.len], digit_solution.steps);
                defer allocator.free(digit_solution.steps);

                trailing_substeps[trailing_substeps.len - 1] = try Step(T).init(
                    try (Expression(T){ .binary = .{
                        .left = &.{ .number = remainder_float },
                        .right = &.{ .binary = .{
                            .left = &.{ .number = b_float },
                            .right = digit_solution.steps[digit_solution.steps.len - 1].after,
                            .operation = .multiplication,
                        } },
                        .operation = .subtraction,
                    } }).clone(allocator),
                    try (Expression(T){ .number = @floatFromInt(@mod(remainder, b_abs)) }).clone(allocator),
                    try std.fmt.allocPrint(allocator, "Subtract {d} from {d}", .{ b_float * digit_solution.steps[digit_solution.steps.len - 1].after.number, remainder }),
                    &.{},
                    allocator,
                );

                try trailing_steps.append(try Step(T).init(
                    try (Expression(T){
                        .binary = .{
                            .left = &.{
                                .function = .{
                                    .name = "divFloor",
                                    .arguments = @constCast(&[_]*const Expression(T){
                                        &.{ .number = remainder_float },
                                        &.{ .number = b_float },
                                    }),
                                    .body = null,
                                },
                            },
                            .right = &.{ .binary = .{
                                .left = &.{ .number = remainder_float },
                                .right = &.{ .number = b_float },
                                .operation = .modulus,
                            } },
                            .operation = .addition,
                        },
                    }).clone(allocator),
                    try (Expression(T){ .binary = .{
                        .left = &.{ .number = @floatFromInt(@divFloor(remainder, b_abs)) },
                        .right = &.{ .number = @floatFromInt(@mod(remainder, b_abs)) },
                        .operation = .addition,
                    } }).clone(allocator),
                    try std.fmt.allocPrint(allocator, "Since {d} is equal to or bigger than {d}, divide it by {d} and append the whole part to the decimal part.\n\nCalculate the next digit, but this time use {d} as the remainder.", .{ remainder, b_abs, b_abs, remainder - digit * b_abs }),
                    trailing_substeps,
                    allocator,
                ));

                remainder -= digit * b_abs;

                const result = decimal + @as(T, @floatFromInt(digit)) * @"10^-x"(trailing_zeroes + i);
                try substeps.append(try Step(T).init(
                    try (Expression(T){ .number = decimal }).clone(allocator),
                    try (Expression(T){ .number = result }).clone(allocator),
                    try allocator.dupe(u8, "Calculate the next digit"),
                    try trailing_steps.toOwnedSlice(),
                    allocator,
                ));

                decimal = result;
                i += trailing_zeroes - 1;
            }

            // since the remainder is 0...?

            solution.steps[2] = try Step(T).init(
                try solution.steps[0].after.clone(allocator),
                try (Expression(T){ .number = (solution.steps[0].after.number) + decimal }).clone(allocator),
                try allocator.dupe(u8, "Calculate the decimal part"),
                try substeps.toOwnedSlice(),
                allocator,
            );

            return solution;
        }

        fn @"10^-x"(x: usize) T {
            var result: T = 10.0;
            for (0..x + 1) |_| {
                result /= 10.0;
            }

            return result;
        }
    };

    // MARK: template
    return Template(Key, T){
        .structure = .{
            .name = "Number division",
            .ast = Expression(T){
                .binary = .{
                    .operation = .division,
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

test division {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = division(T);

        const ten_div_four = testingData(T).get("10 / 4").?;

        const bindings = try Division.structure.matches(ten_div_four);
        const solution = try Division.structure.solve(ten_div_four, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);
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
