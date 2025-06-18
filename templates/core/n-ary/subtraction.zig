pub const Key = usize;

pub fn subtraction(comptime T: type) Template(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T), allocator: std.mem.Allocator) anyerror!Bindings(Key, T) {
            var bindings = try std.ArrayList(*const Expression(T)).initCapacity(allocator, 2);
            var i: usize = 0;

            switch (expression.*) {
                .binary => |binary| {
                    // [...] - (-x) = [...] + x
                    if (expression.binary.operation == .subtraction and expression.binary.right.* == .unary) {
                        try bindings.append(expression.binary.right);
                        return bindings.toOwnedSlice();
                    }

                    if (expression.binary.operation != .subtraction) return error.NotApplicable;

                    const left = try matches(binary.left, allocator);
                    defer allocator.free(left);

                    const right = try matches(binary.right, allocator);
                    defer allocator.free(right);

                    for (0..left.len) |j| {
                        try bindings.append(left[j]);
                        i += 1;
                    }

                    for (0..right.len) |j| {
                        try bindings.append(right[j]);
                        i += 1;
                    }
                },

                .number,
                .variable,
                .boolean,
                .fraction,
                .parenthesis,
                .unary,
                .function,
                => try bindings.append(expression),

                .equation => return error.BinaryEquation,
                .templated => unreachable,
            }

            return bindings.toOwnedSlice();
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const solution = try Solution(T).init(1, allocator);

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .function = .{
                    .name = "sub",
                    .arguments = bindings,
                    .body = null,
                } }).clone(allocator),
            }).clone(allocator);
        }
    };

    return Template(Key, T){ .dynamic = .{
        .name = "N-ary function: subtraction",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

test subtraction {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Addition = subtraction(T);

        const one_three_two = Expression(T){ .binary = .{
            .left = &.{
                .binary = .{
                    .left = &.{ .number = 1.0 },
                    .right = &.{ .number = 3.0 },
                    .operation = .subtraction,
                },
            },
            .right = &.{ .number = 2.0 },
            .operation = .subtraction,
        } };

        const bindings = try Addition.dynamic.matches(&one_three_two, testing.allocator);
        defer testing.allocator.free(bindings);

        const expected: []*const Expression(T) = @constCast(&[_]*const Expression(T){
            &.{ .number = 1.0 },
            &.{ .number = 3.0 },
            &.{ .number = 2.0 },
        });

        try testing.expectEqualDeep(expected, bindings);
    }
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
