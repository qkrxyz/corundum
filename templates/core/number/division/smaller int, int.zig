const Key = template.Templates.get(.@"core/number/division").key;

pub fn @"smaller int, int"(comptime T: type) Variant(Key, T) {
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

            if (bindings.get(.a).?.number > bindings.get(.b).?.number) {
                return error.BIsSmallerThanA;
            }

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = expression;

            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const a_str = try std.fmt.allocPrint(allocator, "{d}", .{a});
            defer allocator.free(a_str);

            const b_str = try std.fmt.allocPrint(allocator, "{d}", .{b});
            defer allocator.free(b_str);

            var steps = std.ArrayList(*const Step(T)).init(allocator);

            // Currently a < b. This means that we need to multiply `a` by 10 until it fits in `b` (a % b >= 1). After that call `int, smaller int`.

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

// test @"smaller int, int" {
//     inline for (.{ f32, f64, f128 }) |T| {
//         const Division = @"smaller int, int"(T);

//         const half_div_two = Expression(T){
//             .binary = .{
//                 .left = &.{ .number = 0.5 },
//                 .right = &.{ .number = 2.0 },
//                 .operation = .division,
//             },
//         };
//     }
// }

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
