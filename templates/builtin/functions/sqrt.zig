pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{});
}

pub const Key = enum { a };

pub fn sqrt(comptime T: type) Template(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            return Bindings(Key, T).init(.{
                .a = expression.function.arguments[0],
            });
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            const a = bindings.get(.a).?;
            _ = a;
            _ = expression;

            const solution = try Solution(T).init(1, true, allocator);
            return solution;
        }
    };

    return Template(Key, T){
        .structure = .{
            .name = "Builtin function: square root",
            .ast = Expression(T){
                .function = .{
                    .name = "sqrt",
                    .arguments = @constCast(&[_]*const Expression(T){&.{ .templated = .number }}),
                    .body = null,
                },
            },
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
