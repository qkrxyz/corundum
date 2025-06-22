pub const Key = enum {
    function,
};

pub fn length(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .function) return error.NotApplicable;

            const bindings = Bindings(Key, T).init(.{
                .function = expression,
            });
            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const function = bindings.get(.function).?;
            const len = function.function.arguments.len;

            const solution = try Solution(T).init(1, allocator);
            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .number = @floatFromInt(len) }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "This function has {d} arguments.", .{len}),
                .substeps = &.{},
            }).clone(allocator);

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .dynamic = .{
            .name = "N-ary function: length",
            .matches = Impl.matches,
            .solve = Impl.solve,
            .variants = &.{},
        },
    };
}

// MARK: tests
test length {
    inline for (.{ f32, f64, f128 }) |T| {
        const Length = length(T);

        inline for (0..20) |i| {
            const avg = Expression(T){ .function = .{
                .name = "average",
                .arguments = @constCast(&[_]*const Expression(T){
                    &.{ .number = 1.0 },
                } ** i),
                .body = null,
            } };

            const bindings = try Length.dynamic.matches(&avg);

            const solution = try Length.dynamic.solve(&avg, bindings, testing.allocator);
            defer solution.deinit(testing.allocator);

            try testing.expectEqual(i, solution.steps[0].after.?.number);
        }
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
