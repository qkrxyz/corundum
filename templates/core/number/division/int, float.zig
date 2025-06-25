pub fn TestingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{});
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
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const division = template.Templates.get(.@"core/number/division").module(T);
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const factor = blk: {
                var i: T = 1.0;
                while (@mod(b * i, 1.0) != 0.0) : (i *= 10.0) {}
                break :blk i;
            };

            const a_multiplied = a * factor;
            const b_multiplied = b * factor;

            var steps = std.ArrayList(*const Step(T)).init(allocator);
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

            const solution = try division.structure.solve(steps.getLast().after.?, Bindings(Key, T).init(.{
                .a = steps.getLast().after.?.binary.left,
                .b = steps.getLast().after.?.binary.right,
            }), allocator);
            try steps.appendSlice(solution.steps);

            defer allocator.free(solution.steps);

            return Solution(T){ .steps = try steps.toOwnedSlice() };
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

// TODO tests

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
