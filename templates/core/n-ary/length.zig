pub const Key = enum {
    length,
};

pub fn length(comptime T: type) Template(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .function) return error.NotApplicable;

            var bindings = Bindings(Key, T).init(.{});
            bindings.put(.length, Expression(T){ .number = expression.function.len });

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const len = bindings.get(.length).?;

            const solution = try Solution(T).init(1, allocator);
            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try len.clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "This function has {d} arguments.", .{len.number}),
                .substeps = &.{},
            }).clone(allocator);

            return solution;
        }
    };

    return Template(Key, T){
        .dynamic = .{
            .name = "N-ary function: length",
            .matches = Impl.matches,
            .solve = Impl.solve,
            .variants = &.{},
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
