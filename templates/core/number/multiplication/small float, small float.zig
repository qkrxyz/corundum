const Key = template.Templates.get(.@"core/number/multiplication").key;

pub fn @"small float, small float"(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates.get(.@"core/number/number").module(T);
            var bindings = Bindings(Key, T).init(.{});

            _ = try number.structure.matches(expression.binary.left);
            bindings.put(.a, expression.binary.left);

            if (@abs(bindings.get(.a).?.number) > 1.0) {
                return error.NotSmallEnough;
            }

            _ = try number.structure.matches(expression.binary.right);
            bindings.put(.b, expression.binary.right);

            if (@abs(bindings.get(.b).?.number) > 1.0) {
                return error.NotSmallEnough;
            }

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.a).?.number;

            const solution = try Solution(T).init(2, allocator);

            const a_str = try std.fmt.allocPrint(allocator, "{d}", .{a});
            defer allocator.free(a_str);

            const b_str = try std.fmt.allocPrint(allocator, "{d}", .{b});
            defer allocator.free(b_str);

            // reinterpret as integers; multiply
            const a_int = try std.fmt.parseFloat(T, a_str[2..]);
            const b_int = try std.fmt.parseFloat(T, b_str[2..]);

            // TODO it can be inaccurate for very long fractions
            const multiplied = a_int * b_int;

            solution.steps[0] = try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .number = multiplied }).clone(allocator),

                .description = try std.fmt.allocPrint(allocator, "Multiply the fractional parts of {d} and {d} as if they were integers", .{ a, b }),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            // pad left
            solution.steps[1] = try (Step(T){
                .before = try solution.steps[0].after.?.clone(allocator),
                .after = try (Expression(T){ .number = std.math.pow(T, 10.0, -@as(f64, @floatFromInt(a_str[2..].len + b_str[2..].len))) * multiplied }).clone(allocator),

                .description = try std.fmt.allocPrint(allocator, "Make the result have {d} decimal places", .{a_str[2..].len + b_str[2..].len}),
                .substeps = try allocator.alloc(*const Step(T), 0),
            }).clone(allocator);

            return solution;
        }
    };

    return Variant(Key, T){
        .name = "Number multiplication: small float × small float",
        .matches = Impl.matches,
        .solve = Impl.solve,
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
