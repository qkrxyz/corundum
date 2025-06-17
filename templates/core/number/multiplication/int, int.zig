const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"int, int"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates.get(.@"core/number/number").module(T);
            var bindings = Bindings(Key, T).init(.{});

            _ = try number.structure.matches(expression.binary.left);
            bindings.put(.a, expression.binary.left);

            if (@rem(bindings.get(.a).?.number, 1.0) != 0.0) {
                return error.NotAnInteger;
            }

            _ = try number.structure.matches(expression.binary.right);
            bindings.put(.b, expression.binary.right);

            if (@rem(bindings.get(.b).?.number, 1.0) != 0.0) {
                return error.NotAnInteger;
            }

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .number = a * b }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ a, b }),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    return Variant(Key, T){
        .name = "Number multiplication: integer × integer",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 5,
    };
}

test "int, int(T).matches" {
    const Multiplication = @"int, int"(f64);

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

    try testing.expectEqual(Bindings(Key, f64).init(.{
        .a = two_times_three.binary.left,
        .b = two_times_three.binary.right,
    }), Multiplication.matches(&two_times_three));
    try testing.expectError(error.NotAnInteger, Multiplication.matches(&half_of_ten));
}

test "int, int(T).solve" {
    const Multiplication = @"int, int"(f64);

    const two_times_three = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 3.0 },
    } };

    const bindings = try Multiplication.matches(&two_times_three);
    const solution = try Multiplication.solve(&two_times_three, bindings, testing.allocator);
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

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
