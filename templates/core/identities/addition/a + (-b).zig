pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1 + (-x)", &Expression(T){ .binary = .{
                .left = &.{ .number = 1.0 },
                .operation = .addition,
                .right = &.{ .unary = .{
                    .operation = .negation,
                    .operand = &.{ .variable = "x" },
                } },
            } },
        },
    });
}

pub const Key = enum {
    a,
    b,
};

pub fn @"a + (-b)"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .addition) return error.NotApplicable;

            const right = expression.binary.right;
            const left = expression.binary.left;

            if (right.* == .unary and right.unary.operation == .negation) {
                return Bindings(Key, T).init(.{
                    .a = left,
                    .b = right.unary.operand,
                });
            } else if (right.* == .number and right.number < 0.0) {
                return Bindings(Key, T).init(.{
                    .a = left,
                    .b = &.{ .number = -right.number },
                });
            }

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;

            const a = bindings.get(.a).?;
            const b = bindings.get(.b).?;

            const solution = try Solution(T).init(1, false, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .binary = .{
                    .left = a,
                    .operation = .subtraction,
                    .right = b,
                } }, allocator),
                try allocator.dupe(u8, "A plus sign and minus sign give together a minus sign"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .dynamic = .{
            .name = "Addition: a + (-b)",
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

// MARK: tests
test @"a + (-b)" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Rewrite = @"a + (-b)"(T);

        const one_plus_minus_x = testingData(T).get("1 + (-x)").?;

        const bindings = try Rewrite.dynamic.matches(one_plus_minus_x);

        try testing.expectEqualDeep(one_plus_minus_x.binary.left, bindings.get(.a).?);
        try testing.expectEqualDeep(one_plus_minus_x.binary.right.unary.operand, bindings.get(.b).?);
    }
}

test "a + (-b)(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Rewrite = @"a + (-b)"(T);

        const one_plus_minus_x = testingData(T).get("1 + (-x)").?;

        const bindings = try Rewrite.dynamic.matches(one_plus_minus_x);
        const solution = try Rewrite.dynamic.solve(one_plus_minus_x, bindings, .default, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = false,
            .steps = @constCast(&[_]*const Step(T){&.{
                .before = one_plus_minus_x,
                .after = &.{ .binary = .{
                    .left = &.{ .number = 1.0 },
                    .operation = .subtraction,
                    .right = &.{ .variable = "x" },
                } },
                .description = "A plus sign and minus sign give together a minus sign",
                .substeps = &.{},
            }}),
        };

        try testing.expectEqualDeep(expected, solution);
    }
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");
const engine = @import("engine");

const Context = engine.Context;
const Expression = expr.Expression;
const Template = template.Template;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
