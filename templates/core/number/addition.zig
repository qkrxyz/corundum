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

            // ±a + b
            if (b > 0.0) {
                const solution = Solution(T){
                    .steps = try allocator.alloc(Step(T), 1),
                };
                solution.steps[0] = Step(T){
                    .before = try expression.clone(allocator),
                    .after = try (Expression(T){ .number = a + b }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ a, b }),
                    .substeps = &.{},
                };

                return solution;
            }

            // ±a + (-b) = ±a - b
            const subtraction = template.Templates(T).get("core/number/subtraction");

            const new_bindings = Bindings(subtraction.key, T).init(.{
                .a = &Expression(T){ .number = a },
                .b = &Expression(T){ .number = -b },
            });
            return subtraction.module.structure.solve(expression, new_bindings, allocator);
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

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
