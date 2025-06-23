pub const Key = enum {
    a,
    b,
};

pub fn division(comptime T: type) Template(Key, T) {
    const variants = @constCast(&template.Templates.variants(.@"core/number/division", T));

    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.binary.left);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            @setFloatMode(.optimized);

            const I = @Type(.{ .int = .{ .bits = @bitSizeOf(T), .signedness = .signed } });
            for (variants) |variant| {
                const new_bindings = variant.matches(expression) catch continue;

                return variant.solve(expression, new_bindings, allocator);
            }

            // guaranteed to be integers
            const a: I = @intFromFloat(bindings.get(.a).?.number);
            const b: I = @intFromFloat(bindings.get(.b).?.number);

            var steps = try std.ArrayList(*const Step(T)).initCapacity(allocator, 2);

            // MARK: integer part
            if (a >= b) {
                const divFloor = template.Templates.get(.@"builtin/functions/divFloor");
                const new_bindings = Bindings(divFloor.key, T).init(.{
                    .a = &.{ .number = @floatFromInt(a) },
                    .b = &.{ .number = @floatFromInt(b) },
                });

                const div_floor_expression = Expression(T){ .function = .{
                    .name = "divFloor",
                    .arguments = @constCast(&[_]*const Expression(T){
                        new_bindings.get(.a).?,
                        new_bindings.get(.b).?,
                    }),
                    .body = null,
                } };

                const solution = try divFloor.module(T).structure.solve(&div_floor_expression, new_bindings, allocator);

                try steps.append(try (Step(T){
                    .before = try div_floor_expression.clone(allocator),
                    .after = try solution.steps[solution.steps.len - 1].after.?.clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Figure out how many times {d} fits in {d}", .{ b, a }),
                    .substeps = solution.steps,
                }).clone(allocator));
            } else {
                try steps.append(try (Step(T){
                    .before = try expression.clone(allocator),
                    .after = try (Expression(T){
                        .function = .{
                            .name = "add",
                            .arguments = @constCast(&[_]*const Expression(T){
                                &.{ .number = 0.0 },
                                &.{ .binary = .{
                                    .left = bindings.get(.a).?,
                                    .right = bindings.get(.b).?,
                                    .operation = .division,
                                } },
                            }),
                            .body = null,
                        },
                    }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Since {d} is smaller than {d}, the integer part of the result is 0.", .{ a, b }),
                    .substeps = &.{},
                }).clone(allocator));
            }

            // MARK: decimal part

            return Solution(T){ .steps = try steps.toOwnedSlice() };
        }
    };

    // MARK: template
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

// TODO tests

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
