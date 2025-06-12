pub const Key = enum {
    a,
    b,
};

pub fn addition(comptime T: type) Template(Key, T) {
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

            // MARK: ±a + b
            if (b > 0.0) {
                const solution = try Solution(T).init(1, allocator);
                solution.steps[0] = try (Step(T){
                    .before = try expression.clone(allocator),
                    .after = try (Expression(T){ .number = a + b }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ a, b }),
                    .substeps = try allocator.alloc(*const Step(T), 0),
                }).clone(allocator);

                return solution;
            }

            // MARK: ±a + (-b) = ±a - b
            const subtraction = template.Templates(T).get("core/number/subtraction");
            const solution = try Solution(T).init(2, allocator);

            const new_bindings = Bindings(subtraction.key, T).init(.{
                .a = &Expression(T){ .number = a },
                .b = &Expression(T){ .number = -b },
            });

            // change the sign
            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){
                    .binary = .{
                        .left = new_bindings.get(.a).?,
                        .operation = .subtraction,
                        .right = new_bindings.get(.b).?,
                    },
                }).clone(allocator),
                .description = try allocator.dupe(u8, "Change the sign"),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            // subtract
            const subtraction_result = try subtraction.module.structure.solve(solution.steps[0].after.?, new_bindings, allocator);
            defer allocator.free(subtraction_result.steps);

            solution.steps[1] = subtraction_result.steps[0];

            return solution;
        }
    };

    return Template(Key, T){
        .structure = .{
            .name = "Number addition",
            .ast = Expression(T){
                .binary = .{
                    .operation = .addition,
                    .left = &Expression(T){ .templated = .number },
                    .right = &Expression(T){ .templated = .number },
                },
            },
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

test addition {
    const Addition = addition(f64);
    const one_plus_two = Expression(f64){ .binary = .{
        .operation = .addition,
        .left = &.{ .number = 1.0 },
        .right = &.{ .number = 2.0 },
    } };

    try testing.expect(Addition.structure.ast.structural() == one_plus_two.structural());
}

test "addition(T).matches" {
    const Addition = addition(f64);

    const one_plus_two = Expression(f64){ .binary = .{
        .operation = .addition,
        .left = &.{ .number = 1.0 },
        .right = &.{ .number = 2.0 },
    } };
    const three_plus_minus_two = Expression(f64){ .binary = .{
        .operation = .addition,
        .left = &.{ .number = 3.0 },
        .right = &.{ .number = -2.0 },
    } };

    var bindings = try Addition.structure.matches(&one_plus_two);
    try testing.expectEqualDeep(bindings.get(.a), one_plus_two.binary.left);
    try testing.expectEqualDeep(bindings.get(.b), one_plus_two.binary.right);

    bindings = try Addition.structure.matches(&three_plus_minus_two);
    try testing.expectEqualDeep(bindings.get(.a), three_plus_minus_two.binary.left);
    try testing.expectEqualDeep(bindings.get(.b), three_plus_minus_two.binary.right);
}

test "addition(T).solve" {
    const Addition = addition(f64);

    const one_plus_two = Expression(f64){ .binary = .{
        .operation = .addition,
        .left = &.{ .number = 1.0 },
        .right = &.{ .number = 2.0 },
    } };

    const bindings = try Addition.structure.matches(&one_plus_two);
    const solution = try Addition.structure.solve(&one_plus_two, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .steps = @constCast(&[_]*const Step(f64){
            &.{
                .before = &one_plus_two,
                .after = &.{ .number = 3.0 },
                .description = "Add 1 and 2 together",
                .substeps = &.{},
            },
        }),
    };

    try testing.expectEqualDeep(expected, solution);
}

test "addition(T).solve - `±a + (-b)`" {
    const Addition = addition(f64);

    const one_plus_two = Expression(f64){ .binary = .{
        .operation = .addition,
        .left = &.{ .number = 1.0 },
        .right = &.{ .number = -2.0 },
    } };

    const one_minus_two = Expression(f64){ .binary = .{
        .operation = .subtraction,
        .left = &.{ .number = 1.0 },
        .right = &.{ .number = 2.0 },
    } };

    const bindings = try Addition.structure.matches(&one_plus_two);
    const solution = try Addition.structure.solve(&one_plus_two, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .steps = @constCast(&[_]*const Step(f64){
            &.{
                .before = &one_plus_two,
                .after = &one_minus_two,
                .description = "Change the sign",
                .substeps = &.{},
            },
            &.{
                .before = &one_minus_two,
                .after = &.{ .number = -1.0 },
                .description = "Subtract 2 from 1",
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
