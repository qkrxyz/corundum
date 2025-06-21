pub const Key = enum {
    a,
    b,
};

pub fn division(comptime T: type) Template(Key, T) {
    const variants = @constCast(&template.Templates.variants(.@"core/number/division", T));

    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const number = comptime template.Templates.get(.@"core/number/number").module(T);
            var bindings = Bindings(Key, T).init(.{});

            _ = try number.structure.matches(expression.binary.left);
            bindings.put(.a, expression.binary.left);

            _ = try number.structure.matches(expression.binary.right);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            for (variants) |variant| {
                const new_bindings = variant.matches(expression) catch continue;

                return variant.solve(expression, new_bindings, allocator);
            }

            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            var steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, 2);

            const a_str = try std.fmt.allocPrint(allocator, "{d}", .{a});
            defer allocator.free(a_str);

            const b_str = try std.fmt.allocPrint(allocator, "{d}", .{b});
            defer allocator.free(b_str);

            // How many times does `a` fit in `b`?
            // We can do this:
            //
            // Before everything, we have some conditions to check:
            // - If `a` < `b`, return 0.
            // - If `a` or `b` is negative, make both positive and set a flag that we need to change the sign of the result.
            //
            // Let's define our multiplier as `x = 1`.
            // At first, multiply x by 10, as long as `b * x <= a`.
            // When `b * x > a`, divide `x` by 10, define `y` as `y = x` and `i` as `i = 1`.
            //
            // As long as y is not equal to one, do the following:
            // Start incrementing i as long as `b * (x + y * i) <= a`; after that
            // `x += (y * (i - 1))`, divide `y` by 10 and set `i` to 1.
            //
            // After that, do the same as the inner loop from the step above:
            // As long as `b * (x + i) <= a`, increment `i` by one.
            // Lastly, add `y * (i - 1)` to `x`.
            // `x` is your result.
            //
            // Compared to the usual "bring digits down until it fits", you can very quickly approximate this
            // (e.g. on the side or even in your head) by looking at the lengths of a and b, and only then actually writing something down.
            //
            // e.g. for 7393/23, b (and the multiplier) would take this journey:
            // - 23, 230, 2300, 23000, 2300   | 1, 10, 100, 1000, 100
            // - 2300, 4600, 6900, 9200, 6900 | 100, 200, 300, 400, 300
            // - 6900, 7130, 7360, 7590, 7360 | 300, 310, 320, 330, 320
            // - 7360, 7383, 7406, 7383       | 320, 321, 322, 321
            // Since we can't increment the multiplier by a value lower than 1, we have our result.
            //
            // TODO actually implement this

            return Solution(T){ .steps = try steps.toOwnedSlice() };
        }
    };

    return Template(Key, T){
        .structure = .{
            .name = "Number division",
            .ast = Expression(T){
                .binary = .{
                    .operation = .division,
                    .left = &Expression(T){ .templated = .number },
                    .right = &Expression(T){ .templated = .number },
                },
            },
            .matches = Impl.matches,
            .solve = Impl.solve,
            .variants = variants,
        },
    };
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
