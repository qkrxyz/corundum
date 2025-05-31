pub fn structural(comptime T: type, expression: *const Expression(T), hasher: anytype) void {
    const Hasher = switch (@typeInfo(@TypeOf(hasher))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(hasher),
    };

    if (expression.* == .templated) {
        @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(expression.templated)} });
        return;
    }

    @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(expression.*)} });

    switch (expression.*) {
        .number, .variable, .boolean => return,
        .fraction => {
            structural(T, expression.fraction.numerator, hasher);
            structural(T, expression.fraction.denominator, hasher);
        },
        .equation => {
            structural(T, expression.equation.left, hasher);
            structural(T, expression.equation.right, hasher);
            @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(expression.equation.sign)} });
        },
        .binary => {
            structural(T, expression.binary.left, hasher);
            structural(T, expression.binary.right, hasher);
            @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(expression.binary.operation)} });
        },
        .unary => {
            structural(T, expression.unary.operand, hasher);
            @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(expression.unary.operation)} });
        },
        .function => {
            @call(.always_inline, Hasher.update, .{ hasher, &std.mem.toBytes(@as(usize, expression.function.arguments.len)) });

            for (expression.function.arguments) |argument| {
                structural(T, argument, hasher);
            }

            if (expression.function.body) |body| structural(T, body, hasher);
        },
        .templated => unreachable,
    }
}

test structural {
    const one = Expression(f64){ .number = 1.0 };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &one, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const two = Expression(f64){ .number = 2.0 };
    structural(f64, &two, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});

        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(variable)" {
    const x = Expression(f64){ .variable = "x" };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &x, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const y = Expression(f64){ .variable = "y" };
    structural(f64, &y, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(boolean)" {
    const @"true" = Expression(f64){ .boolean = true };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &@"true", &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const @"false" = Expression(f64){ .boolean = false };
    structural(f64, &@"false", &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.boolean)});
        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(fraction)" {
    const pi_2 = Expression(f64){ .fraction = .{
        .numerator = &.{ .variable = "pi" },
        .denominator = &.{ .number = 2.0 },
    } };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &pi_2, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const pi_3 = Expression(f64){ .fraction = .{
        .numerator = &.{ .variable = "pi" },
        .denominator = &.{ .number = 3.0 },
    } };
    structural(f64, &pi_3, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.fraction)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});

        break :blk hasher.final();
    };
    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(equation)" {
    const x_equals_two = Expression(f64){ .equation = .{
        .left = &.{ .variable = "pi" },
        .right = &.{ .number = 2.0 },
        .sign = .equals,
    } };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &x_equals_two, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const y_equals_three = Expression(f64){ .equation = .{
        .left = &.{ .variable = "y" },
        .right = &.{ .number = 3.0 },
        .sign = .equals,
    } };
    structural(f64, &y_equals_three, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.equation)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).Sign.equals)});

        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(binary)" {
    const x_plus_two = Expression(f64){ .binary = .{
        .left = &.{ .variable = "x" },
        .right = &.{ .number = 2.0 },
        .operation = .addition,
    } };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &x_plus_two, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const y_plus_three = Expression(f64){ .binary = .{
        .left = &.{ .variable = "y" },
        .right = &.{ .number = 3.0 },
        .operation = .addition,
    } };
    structural(f64, &y_plus_three, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.binary)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).BinaryOperation.addition)});

        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(unary)" {
    const x_degree = Expression(f64){ .unary = .{
        .operand = &.{ .variable = "x" },
        .operation = .degree,
    } };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &x_degree, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const y_degree = Expression(f64){ .unary = .{
        .operand = &.{ .variable = "y" },
        .operation = .degree,
    } };
    structural(f64, &y_degree, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.unary)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).UnaryOperation.degree)});

        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(function)" {
    const sin = Expression(f64){ .function = .{
        .name = "sin",
        .arguments = @ptrCast(@constCast(&[_]*const Expression(f64){
            &.{ .variable = "x" },
        })),
        .body = null,
    } };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &sin, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const cos = Expression(f64){ .function = .{
        .name = "cos",
        .arguments = @ptrCast(@constCast(&[_]*const Expression(f64){
            &.{ .variable = "y" },
        })),
        .body = null,
    } };
    structural(f64, &cos, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.function)});
        hasher.update(&std.mem.toBytes(@as(usize, 1)));
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});

        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
}

test "structural(templated)" {
    const number_addition = Expression(f64){ .binary = .{
        .left = &.{ .templated = .number },
        .right = &.{ .templated = .number },
        .operation = .addition,
    } };

    var hasher = std.hash.XxHash64.init(0);
    structural(f64, &number_addition, &hasher);
    const result = hasher.final();

    hasher = std.hash.XxHash64.init(0);
    const one_plus_two = Expression(f64){ .binary = .{
        .left = &.{ .number = 1.0 },
        .right = &.{ .number = 2.0 },
        .operation = .addition,
    } };
    structural(f64, &one_plus_two, &hasher);
    const result2 = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.binary)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).BinaryOperation.addition)});

        break :blk hasher.final();
    };

    try std.testing.expectEqual(expected, result);
    try std.testing.expectEqual(expected, result2);
    try std.testing.expectEqual(result, result2);
}

const std = @import("std");
const expr = @import("expr");
const Expression = @import("expr").Expression;
