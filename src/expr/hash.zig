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

        hasher.update(&[_]u8{@intFromEnum(@import("expr").Kind.number)});
        hasher.update(&std.mem.toBytes(@as(f64, 1.0)));

        break :blk hasher.final();
    };

    try testing.expectEqual(expected, result);
}

const std = @import("std");
const testing = std.testing;

const Expression = @import("expr").Expression;
