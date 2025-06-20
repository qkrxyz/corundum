const Key = template.Templates.get(.@"core/number/division").key;

pub fn @"int, smaller int"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.binary.left);
            if (@mod(bindings.get(.a).?.number, 1.0) != 0.0) {
                return error.NotAnInteger;
            }

            bindings.put(.b, expression.binary.right);
            if (@mod(bindings.get(.b).?.number, 1.0) != 0.0) {
                return error.NotAnInteger;
            }

            if (bindings.get(.a).?.number < bindings.get(.b).?.number) {
                return error.AIsSmallerThanB;
            }

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const a_str = try std.fmt.allocPrint(allocator, "{d}", .{a});
            defer allocator.free(a_str);

            const b_str = try std.fmt.allocPrint(allocator, "{d}", .{b});
            defer allocator.free(b_str);

            var steps = std.ArrayList(*const Step(T)).init(allocator);

            // first division will always result in a number bigger than one, since a / b >= 1 when a > b
            const first_a = try std.fmt.parseFloat(T, a_str[0..b_str.len]);

            try steps.append(try (Step(T){
                .before = try (Expression(T){ .binary = .{
                    .left = &.{ .number = first_a },
                    .right = &.{ .number = b },
                    .operation = .modulus,
                } }).clone(allocator),
                .after = try (Expression(T){ .number = @mod(first_a, b) }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Calculate how many times {d} fits in {d}", .{ first_a, b }),
                .substeps = &.{},
            }).clone(allocator));

            const new_bindings = Bindings(Key, T).init(.{
                .a = try (Expression(T){ .number = a - @mod(first_a, b) * b }).clone(allocator),
                .b = try bindings.get(.b).?.clone(allocator),
            });

            try steps.append(try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .binary = .{
                    .left = new_bindings.get(.a).?,
                    .right = new_bindings.get(.b).?,
                    .operation = .division,
                } }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Subtract {d} from {d}, and divide again", .{ @mod(first_a, b) * b, a }),
                .substeps = &.{},
            }).clone(allocator));

            // now that a < b, we should use the `smaller int, int` template that handles these cases.
            // TODO implement `smaller int, int` template

            return Solution(T){ .steps = try steps.toOwnedSlice() };
        }
    };

    return Variant(Key, T){
        .name = "Number division: int, int - a ≥ b",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 2,
    };
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
