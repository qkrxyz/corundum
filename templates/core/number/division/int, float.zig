pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "45 / 1.5", &Expression(T){
                .binary = .{
                    .left = &.{ .number = 45 },
                    .right = &.{ .number = 1.5 },
                    .operation = .division,
                },
            },
        },
    });
}

const Key = template.Templates.get(.@"core/number/division").key;

pub fn @"int, float"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.binary.left);
            if (@mod(bindings.get(.a).?.number, 1.0) != 0.0) {
                return error.NotAnInteger;
            }

            bindings.put(.b, expression.binary.right);
            if (@mod(bindings.get(.b).?.number, 1.0) == 0.0) {
                return error.NotAFloat;
            }

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            @setFloatMode(.optimized);

            const division = template.Templates.get(.@"core/number/division").module(T);
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            // shift
            const factor = blk: {
                var i: T = 1.0;
                while (@mod(b * i, 1.0) != 0.0) : (i *= 10.0) {}
                break :blk i;
            };

            const a_multiplied = a * factor;
            const b_multiplied = b * factor;

            // division
            const division_solution = try division.structure.solve(&Expression(T){ .binary = .{
                .left = &.{ .number = a_multiplied },
                .right = &.{ .number = b_multiplied },
                .operation = .division,
            } }, Bindings(Key, T).init(.{
                .a = &.{ .number = a_multiplied },
                .b = &.{ .number = b_multiplied },
            }), allocator);

            const solution = try Solution(T).init(division_solution.steps.len + 1, true, allocator);

            // combine steps
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{
                    .binary = .{
                        .left = &.{ .number = a_multiplied },
                        .right = &.{ .number = b_multiplied },
                        .operation = .division,
                    },
                }, allocator),
                try std.fmt.allocPrint(allocator, "Shift both numbers' decimal points by {d} places right", .{@log10(factor)}),

                // TODO populate this with steps from the `factor` blk
                &.{},
                allocator,
            );

            @memcpy(solution.steps[1..solution.steps.len], division_solution.steps);
            defer allocator.free(division_solution.steps);

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number division: integer / float",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 50,
    };
}

test @"int, float" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"int, float"(T);

        const fourty_five_div_three_halves = testingData(T).get("45 / 1.5").?;

        const bindings = try Division.matches(fourty_five_div_three_halves);
        const solution = try Division.solve(fourty_five_div_three_halves, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);
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
