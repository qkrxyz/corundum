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

            // ±a - b
            if (b > 0.0) {
                const solution = Solution(T){
                    .steps = try allocator.alloc(Step(T), 1),
                };
                solution.steps[0] = Step(T){
                    .before = try expression.clone(allocator),
                    .after = try (Expression(T){ .number = a - b }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Subtract {d} from {d} together", .{ b, a }),
                    .substeps = &.{},
                };

                return solution;
            }

            // ±a - (-b) = ±a + b
            const addition = template.Templates(T).get("core/number/addition");

            const new_bindings = Bindings(addition.key, T).init(.{
                .a = &Expression(T){ .number = a },
                .b = &Expression(T){ .number = -b },
            });
            return addition.module.structure.solve(expression, new_bindings, allocator);
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

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
