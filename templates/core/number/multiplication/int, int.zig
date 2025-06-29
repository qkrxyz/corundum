pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "2 * 3", &Expression(T){ .binary = .{
                .operation = .multiplication,
                .left = &.{ .number = 2.0 },
                .right = &.{ .number = 3.0 },
            } },
        },
    });
}

const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"int, int"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.binary.left);
            if (@mod(bindings.get(.a).?.number, 1.0) != 0.0) {
                return error.NotAnInteger;
            }

            bindings.put(.b, expression.binary.right);
            if (@mod(bindings.get(.b).?.number, 1.0) != 0.0) {
                return error.NotAnInteger;
            }

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try (Expression(T){ .number = a * b }).clone(allocator),
                try std.fmt.allocPrint(allocator, "Multiply {d} by {d}", .{ a, b }),

                // TODO actually do solution steps
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number multiplication: integer × integer",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 1,
    };
}

// MARK: tests
test "int, int(T).matches" {
    const Multiplication = @"int, int"(f64);

    const two_times_three = testingData(f64).get("2 * 3").?;

    const half_of_ten = Expression(f64){ .binary = .{
        .operation = .multiplication,
        .left = &.{ .number = 0.5 },
        .right = &.{ .number = 10.0 },
    } };

    try testing.expectEqual(Bindings(Key, f64).init(.{
        .a = two_times_three.binary.left,
        .b = two_times_three.binary.right,
    }), Multiplication.matches(two_times_three));

    try testing.expectError(error.NotAnInteger, Multiplication.matches(&half_of_ten));
}

test "int, int(T).solve" {
    const Multiplication = @"int, int"(f64);

    const two_times_three = testingData(f64).get("2 * 3").?;

    const bindings = try Multiplication.matches(two_times_three);
    const solution = try Multiplication.solve(two_times_three, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .is_final = true,
        .steps = @constCast(&[_]*const Step(f64){
            &.{
                .before = two_times_three,
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
