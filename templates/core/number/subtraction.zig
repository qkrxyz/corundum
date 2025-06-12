pub const Key = enum {
    a,
    b,
};

pub fn subtraction(comptime T: type) Template(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates(T).get("core/number/number");
            var bindings = Bindings(Key, T).init(.{});

            _ = try number.module.structure.matches(expression.binary.left);
            bindings.put(.a, expression.binary.left);

            _ = try number.module.structure.matches(expression.binary.right);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            // MARK: ±a - b
            if (b > 0.0) {
                const solution = try Solution(T).init(1, allocator);

                solution.steps[0] = try (Step(T){
                    .before = try expression.clone(allocator),
                    .after = try (Expression(T){ .number = a - b }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Subtract {d} from {d}", .{ b, a }),
                    .substeps = try allocator.alloc(*const Step(T), 0),
                }).clone(allocator);

                return solution;
            }

            // MARK: ±a - (-b) = ±a + b
            const addition = template.Templates(T).get("core/number/addition");
            const solution = try Solution(T).init(2, allocator);

            const new_bindings = Bindings(addition.key, T).init(.{
                .a = &Expression(T){ .number = a },
                .b = &Expression(T){ .number = -b },
            });

            // change the sign
            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){
                    .binary = .{
                        .left = new_bindings.get(.a).?,
                        .operation = .addition,
                        .right = new_bindings.get(.b).?,
                    },
                }).clone(allocator),
                .description = try allocator.dupe(u8, "Change the sign"),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            // subtract
            const addition_result = try addition.module.structure.solve(solution.steps[0].after.?, new_bindings, allocator);
            defer allocator.free(addition_result.steps);

            solution.steps[1] = addition_result.steps[0];

            return solution;
        }
    };

    return Template(Key, T){
        .structure = .{
            .name = "Number subtraction",
            .ast = Expression(T){
                .binary = .{
                    .operation = .subtraction,
                    .left = &Expression(T){ .templated = .number },
                    .right = &Expression(T){ .templated = .number },
                },
            },
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

test subtraction {
    const Subtraction = subtraction(f64);
    const two_minus_one = Expression(f64){ .binary = .{
        .operation = .subtraction,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 1.0 },
    } };

    try testing.expect(Subtraction.structure.ast.structural() == two_minus_one.structural());
}

test "subtraction(T).matches" {
    const Subtraction = subtraction(f64);

    const two_minus_one = Expression(f64){ .binary = .{
        .operation = .subtraction,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 1.0 },
    } };
    const three_minus_minus_two = Expression(f64){ .binary = .{
        .operation = .subtraction,
        .left = &.{ .number = 3.0 },
        .right = &.{ .number = -2.0 },
    } };

    var bindings = try Subtraction.structure.matches(&two_minus_one);
    try testing.expectEqualDeep(bindings.get(.a), two_minus_one.binary.left);
    try testing.expectEqualDeep(bindings.get(.b), two_minus_one.binary.right);

    bindings = try Subtraction.structure.matches(&three_minus_minus_two);
    try testing.expectEqualDeep(bindings.get(.a), three_minus_minus_two.binary.left);
    try testing.expectEqualDeep(bindings.get(.b), three_minus_minus_two.binary.right);
}

test "subtraction(T).solve" {
    const Subtraction = subtraction(f64);

    const two_minus_one = Expression(f64){ .binary = .{
        .operation = .subtraction,
        .left = &.{ .number = 2.0 },
        .right = &.{ .number = 1.0 },
    } };

    const bindings = try Subtraction.structure.matches(&two_minus_one);
    const solution = try Subtraction.structure.solve(&two_minus_one, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .steps = @constCast(&[_]*const Step(f64){
            &.{
                .before = &two_minus_one,
                .after = &.{ .number = 1.0 },
                .description = "Subtract 1 from 2",
                .substeps = &.{},
            },
        }),
    };

    try testing.expectEqualDeep(expected, solution);
}

test "subtraction(T).solve - `±a - (-b)`" {
    const Subtraction = subtraction(f64);

    const three_minus_minus_two = Expression(f64){ .binary = .{
        .operation = .subtraction,
        .left = &.{ .number = 3.0 },
        .right = &.{ .number = -2.0 },
    } };

    const three_plus_two = Expression(f64){ .binary = .{
        .operation = .addition,
        .left = &.{ .number = 3.0 },
        .right = &.{ .number = 2.0 },
    } };

    const bindings = try Subtraction.structure.matches(&three_minus_minus_two);
    const solution = try Subtraction.structure.solve(&three_minus_minus_two, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .steps = @constCast(&[_]*const Step(f64){
            &.{
                .before = &three_minus_minus_two,
                .after = &three_plus_two,
                .description = "Change the sign",
                .substeps = &.{},
            },
            &.{
                .before = &three_plus_two,
                .after = &.{ .number = 5.0 },
                .description = "Add 3 and 2 together",
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
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
