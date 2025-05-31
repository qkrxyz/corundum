pub fn hash(comptime T: type, expression: *const Expression(T), hasher: anytype) void {
    const Hasher = switch (@typeInfo(@TypeOf(hasher))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(hasher),
    };

    @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(expression.*)} });

    switch (expression.*) {
        .number => |number| @call(.always_inline, Hasher.update, .{ hasher, &std.mem.toBytes(number) }),
        .variable => |variable| @call(.always_inline, Hasher.update, .{ hasher, variable }),
        .boolean => |boolean| @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromBool(boolean)} }),
        .fraction => |fraction| {
            hash(T, fraction.numerator, hasher);
            hash(T, fraction.denominator, hasher);
        },
        .equation => |equation| {
            hash(T, equation.left, hasher);
            hash(T, equation.right, hasher);
            @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(equation.sign)} });
        },
        .binary => |binary| {
            hash(T, binary.left, hasher);
            hash(T, binary.right, hasher);
            @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(binary.operation)} });
        },
        .unary => |unary| {
            hash(T, unary.operand, hasher);
            @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(unary.operation)} });
        },
        .function => |function| {
            @call(.always_inline, Hasher.update, .{ hasher, function.name });
            @call(.always_inline, Hasher.update, .{ hasher, &std.mem.toBytes(@as(usize, function.arguments.len)) });

            for (function.arguments) |argument| {
                hash(T, argument, hasher);
            }

            if (function.body) |body| hash(T, body, hasher);
        },
        .templated => |kind| @call(.always_inline, Hasher.update, .{ hasher, &[_]u8{@intFromEnum(kind)} }),
    }
}

test hash {
    const one = Expression(f64){ .number = 1.0 };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &one, &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&std.mem.toBytes(@as(f64, 1.0)));

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(variable)" {
    const x = Expression(f64){ .variable = "x" };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &x, &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{'x'});

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(boolean)" {
    const @"true" = Expression(f64){ .boolean = true };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &@"true", &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.boolean)});
        hasher.update(&[_]u8{@intFromBool(true)});

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(fraction)" {
    const pi_2 = Expression(f64){ .fraction = .{
        .numerator = &.{ .variable = "pi" },
        .denominator = &.{ .number = 2.0 },
    } };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &pi_2, &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.fraction)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{ 'p', 'i' });
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&std.mem.toBytes(@as(f64, 2.0)));

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(equation)" {
    const x_equals_2 = Expression(f64){ .equation = .{
        .left = &.{ .variable = "x" },
        .right = &.{ .number = 2.0 },
        .sign = .equals,
    } };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &x_equals_2, &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.equation)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{'x'});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&std.mem.toBytes(@as(f64, 2.0)));
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).Sign.equals)});

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(binary)" {
    const x_plus_2 = Expression(f64){ .binary = .{
        .left = &.{ .variable = "x" },
        .right = &.{ .number = 2.0 },
        .operation = .addition,
    } };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &x_plus_2, &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.binary)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{'x'});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&std.mem.toBytes(@as(f64, 2.0)));
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).BinaryOperation.addition)});

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(unary)" {
    const @"30_deg" = Expression(f64){ .unary = .{
        .operand = &.{ .number = 30.0 },
        .operation = .degree,
    } };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &@"30_deg", &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.unary)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&std.mem.toBytes(@as(f64, 30.0)));
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).UnaryOperation.degree)});

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(function)" {
    const sin = Expression(f64){ .function = .{
        .name = "sin",
        .arguments = @ptrCast(@constCast(&[_]*const Expression(f64){
            &.{ .variable = "x" },
        })),
        .body = null,
    } };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &sin, &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.function)});
        hasher.update(&[_]u8{ 's', 'i', 'n' });
        hasher.update(&std.mem.toBytes(@as(usize, 1)));
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.variable)});
        hasher.update(&[_]u8{'x'});

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

test "hash(templated)" {
    const addition = Expression(f64){ .binary = .{
        .left = &.{ .templated = .number },
        .right = &.{ .templated = .number },
        .operation = .addition,
    } };

    var hasher = std.hash.XxHash64.init(0);
    hash(f64, &addition, &hasher);
    const result = hasher.final();

    const expected = blk: {
        hasher = std.hash.XxHash64.init(0);

        hasher.update(&[_]u8{@intFromEnum(expr.Kind.binary)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.templated)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.templated)});
        hasher.update(&[_]u8{@intFromEnum(expr.Kind.number)});
        hasher.update(&[_]u8{@intFromEnum(expr.Expression(f64).BinaryOperation.addition)});

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const Expression = expr.Expression;
