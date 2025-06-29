pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "4 / 1", &Expression(T){ .binary = .{
                .left = &.{ .number = 4.0 },
                .right = &.{ .number = 1.0 },
                .operation = .division,
            } },
        },
    });
}

const Key = template.Templates.get(.@"core/number/division").key;

pub fn @"a ÷ 1"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.binary.right.number == 1.0) return Bindings(Key, T).init(.{
                .a = expression.binary.left,
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try a.clone(allocator),
                try allocator.dupe(u8, "Division by one does nothing"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number division: a ÷ 1",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 999,
    };
}

// MARK: tests
test @"a ÷ 1" {
    inline for (.{ f16, f32, f64, f128 }) |T| {
        const Division = @"a ÷ 1"(T);

        const four_div_1 = testingData(T).get("4 / 1").?;

        const bindings = try Division.matches(four_div_1);
        const solution = try Division.solve(four_div_1, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = four_div_1,
                    .after = &.{ .number = 4.0 },
                    .description = "Division by one does nothing",
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

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
