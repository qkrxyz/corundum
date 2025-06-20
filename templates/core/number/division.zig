pub const Key = enum {
    a,
    b,
};

pub fn division(comptime T: type) Template(Key, T) {
    const variants = @constCast(&template.Templates.variants(.@"core/number/division", T));

    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates.get(.@"core/number/number").module(T);
            var bindings = Bindings(Key, T).init(.{});

            _ = try number.structure.matches(expression.binary.left);
            bindings.put(.a, expression.binary.left);

            _ = try number.structure.matches(expression.binary.right);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            for (variants) |variant| {
                const new_bindings = variant.matches(expression) catch continue;

                return variant.solve(expression, new_bindings, allocator);
            }

            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            var steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, 1);

            try steps.append(try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .fraction = .{
                    .numerator = bindings.get(.a).?,
                    .denominator = bindings.get(.b).?,
                } }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Divide {d} by {d}", .{ a, b }),
                .substeps = &.{},
            }).clone(allocator));

            return Solution(T){ .steps = try steps.toOwnedSlice() };
        }
    };

    return Template(Key, T){
        .structure = .{
            .name = "Number division",
            .ast = Expression(T){
                .binary = .{
                    .operation = .division,
                    .left = &Expression(T){ .templated = .number },
                    .right = &Expression(T){ .templated = .number },
                },
            },
            .matches = Impl.matches,
            .solve = Impl.solve,
            .variants = variants,
        },
    };
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Template = template.Template;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
