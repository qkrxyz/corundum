pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "0.5 * 3.0", &Expression(T){ .binary = .{
                .operation = .multiplication,
                .left = &.{ .number = 0.5 },
                .right = &.{ .number = 3.0 },
            } },
        },
    });
}

const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"small float, int"(comptime T: type) Variant(Key, T) {
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

            if (@abs(bindings.get(.a).?.number) > 1.0) {
                return error.NotSmallEnough;
            }

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;
            @setFloatMode(.optimized);

            const I = @Type(.{ .int = .{ .bits = @bitSizeOf(T), .signedness = .unsigned } });

            const a, const b = .{ bindings.get(.a).?.number, bindings.get(.b).?.number };

            const solution = try Solution(T).init(2, true, allocator);

            // MARK: reinterpret d as integer; multiply
            const a_str = try std.fmt.allocPrint(allocator, "{d}", .{a});
            defer allocator.free(a_str);

            const a_int = std.fmt.parseFloat(T, a_str[2..]) catch unreachable;
            const multiplied = a_int * b;

            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .number = multiplied }, allocator),
                try std.fmt.allocPrint(allocator, "Multiply the fractional part of {d} (as if it was an integer - {d}) with {d}", .{ a, a_int, b }),
                &.{},
                allocator,
            );

            // MARK: shift
            const b_len = b_len_blk: {
                const truncated: I = @intFromFloat(@trunc(b));

                var i: I = 0;
                while (std.math.powi(I, 10, i) catch unreachable <= truncated) : (i += 1) {}

                break :b_len_blk i;
            };
            const shift: I = @intCast(b_len + a_str[2..].len);

            solution.steps[1] = try Step(T).init(
                try solution.steps[0].after.clone(allocator),
                try (Expression(T){
                    .number = multiplied / @as(T, @floatFromInt(std.math.powi(I, 10, shift - 1) catch unreachable)),
                }).clone(allocator),
                try std.fmt.allocPrint(allocator, "Move the decimal point left by {d} place(-s)", .{shift - 1}),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number multiplication: small float × integer",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 3,
    };
}

// MARK: tests
test "small float, int(T).matches" {
    const Multiplication = @"small float, int"(f64);

    const two_times_three = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 3.0 },
    } };

    const half_of_ten = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 0.5 },
        .right = &.{ .number = 10.0 },
    } };

    const three_halves_of_two = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 1.5 },
        .right = &.{ .number = 2.0 },
    } };

    const half_of_quarter = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 0.5 },
        .right = &.{ .number = 0.25 },
    } };

    try testing.expectEqual(Bindings(Key, f64).init(.{
        .a = half_of_ten.binary.left,
        .b = half_of_ten.binary.right,
    }), Multiplication.matches(&half_of_ten));

    try testing.expectError(error.NoFloatAndInt, Multiplication.matches(&two_times_three));
    try testing.expectError(error.NoFloatAndInt, Multiplication.matches(&half_of_quarter));
    try testing.expectError(error.NotSmallEnough, Multiplication.matches(&three_halves_of_two));
}

test "small float, int(T).solve" {
    const Multiplication = @"small float, int"(f64);

    const half_of_three = testingData(f64).get("0.5 * 3.0").?;

    const bindings = try Multiplication.matches(half_of_three);
    const solution = try Multiplication.solve(half_of_three, bindings, .default, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .is_final = true,
        .steps = @constCast(&[_]*const Step(f64){
            // step 1: reinterpret; multiply
            &.{
                .before = half_of_three,
                .after = &.{ .number = 15.0 },
                .description = "Multiply the fractional part of 0.5 (as if it was an integer - 5) with 3",
                .substeps = &.{},
            },

            // step 2: shift
            &.{
                .before = &.{ .number = 15.0 },
                .after = &.{ .number = 1.5 },
                .description = "Move the decimal point left by 1 place(-s)",
                .substeps = &.{},
            },
        }),
    };

    try testing.expectEqualDeep(expected, solution);
}

const std = @import("std");
const testing = std.testing;
const engine = @import("engine");

const Context = engine.Context;
const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
