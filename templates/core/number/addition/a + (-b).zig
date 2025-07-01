pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1 + (-3)", &Expression(T){ .binary = .{
                .left = &.{ .number = 1.0 },
                .operation = .addition,
                .right = &.{ .number = -3.0 },
            } },
        },
    });
}

const Key = template.Templates.get(.@"core/number/addition").key;

pub fn @"a + (-b)"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const left = expression.binary.left;
            const right = expression.binary.right;

            if (right.* == .number and right.number < 0.0) {
                const bindings = Bindings(Key, T).init(.{
                    .a = left,
                    .b = right,
                });
                return bindings;
            }

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            const a = bindings.get(.a).?;
            const b = bindings.get(.b).?;

            const solution = try Solution(T).init(2, false, allocator);

            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .binary = .{
                    .left = a,
                    .operation = .subtraction,
                    .right = &.{ .number = -b.number },
                } }, allocator),
                try allocator.dupe(u8, "A plus sign and minus sign give together a minus sign"),
                &.{},
                allocator,
            );

            const subtraction = template.Templates.get(.@"core/number/subtraction");

            const subtraction_result = try subtraction.module(T).structure.solve(
                solution.steps[0].after,
                Bindings(subtraction.key, T).init(.{
                    .a = a,
                    .b = solution.steps[0].after.binary.right,
                }),
                context,
                allocator,
            );
            defer allocator.free(subtraction_result.steps);

            solution.steps[1] = subtraction_result.steps[0];
            return solution;
        }
    };

    // MARK: template
    return Variant(Key, T){
        .name = "Number addition: a + (-b)",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 100,
    };
}

// MARK: tests
test @"a + (-b)" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Rewrite = @"a + (-b)"(T);

        const one_plus_minus_three = testingData(T).get("1 + (-3)").?;

        const bindings = try Rewrite.matches(one_plus_minus_three);
        try testing.expectEqualDeep(&Expression(T){ .number = 1.0 }, bindings.get(.a).?);
        try testing.expectEqualDeep(&Expression(T){ .number = -3.0 }, bindings.get(.b).?);
    }
}

test "a + (-b)(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Rewrite = @"a + (-b)"(T);

        const input = testingData(T).get("1 + (-3)").?;

        const bindings = try Rewrite.matches(input);
        const solution = try Rewrite.solve(input, bindings, .default, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = false,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = input,
                    .after = &.{ .binary = .{
                        .left = &.{ .number = 1.0 },
                        .operation = .subtraction,
                        .right = &.{ .number = 3.0 },
                    } },
                    .description = "A plus sign and minus sign give together a minus sign",
                    .substeps = &.{},
                },
                &.{
                    .before = &.{ .binary = .{
                        .left = &.{ .number = 1.0 },
                        .operation = .subtraction,
                        .right = &.{ .number = 3.0 },
                    } },
                    .after = &.{ .number = -2.0 },
                    .description = "Subtract 3 from 1",
                    .substeps = &.{},
                },
            }),
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
