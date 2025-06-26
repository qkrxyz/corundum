pub fn TestingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{ "4.5 / 1.5", &Expression(T){
            .binary = .{
                .left = &.{ .number = 4.5 },
                .right = &.{ .number = 1.5 },
                .operation = .division,
            },
        } },
    });
}

const Key = template.Templates.get(.@"core/number/division").key;

pub fn @"float, float"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.binary.left);
            if (@mod(bindings.get(.a).?.number, 1.0) == 0.0) {
                return error.NotAFloat;
            }

            bindings.put(.b, expression.binary.right);
            if (@mod(bindings.get(.b).?.number, 1.0) == 0.0) {
                return error.NotAFloat;
            }

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const division = template.Templates.get(.@"core/number/division").module(T);
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            // shift
            const factor = blk: {
                var i: T = 1.0;
                while (@mod(b * i, 1.0) != 0.0 or @mod(a * i, 1.0) != 0.0) : (i *= 10.0) {}
                break :blk i;
            };

            const a_multiplied = a * factor;
            const b_multiplied = b * factor;

            // division
            const solution = try division.structure.solve(&Expression(T){ .binary = .{
                .left = &.{ .number = a_multiplied },
                .right = &.{ .number = b_multiplied },
                .operation = .division,
            } }, Bindings(Key, T).init(.{
                .a = &.{ .number = a_multiplied },
                .b = &.{ .number = b_multiplied },
            }), allocator);

            // combine steps
            var steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, solution.steps.len + 1);

            try steps.append(try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){
                    .binary = .{
                        .left = &.{ .number = a_multiplied },
                        .right = &.{ .number = b_multiplied },
                        .operation = .division,
                    },
                }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Shift both numbers' decimal points by {d} places right", .{@log10(factor)}),

                // TODO populate this with steps from the `factor` blk
                .substeps = &.{},
            }).clone(allocator));

            try steps.appendSlice(solution.steps);
            allocator.free(solution.steps);

            return Solution(T){ .steps = try steps.toOwnedSlice() };
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Number division: float / float",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 50,
    };
}

test @"float, float" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Division = @"float, float"(T);

        const four_half_div_one_half = TestingData(T).get("4.5 / 1.5").?;

        const bindings = try Division.matches(four_half_div_one_half);
        const solution = try Division.solve(four_half_div_one_half, bindings, testing.allocator);
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
