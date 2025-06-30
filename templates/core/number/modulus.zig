pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "10 % 4", &Expression(T){ .binary = .{
                .operation = .modulus,
                .left = &.{ .number = 10.0 },
                .right = &.{ .number = 4.0 },
            } },
        },
    });
}

pub const Key = enum {
    a,
    b,
};

pub fn modulus(comptime T: type) Template(Key, T) {
    const Impl = struct {
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            return Bindings(Key, T).init(.{
                .a = expression.binary.left,
                .b = expression.binary.right,
            });
        }

        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            @setFloatMode(.optimized);

            const a = bindings.get(.a).?;
            const b = bindings.get(.b).?;

            const solution = try Solution(T).init(2, true, allocator);

            const divFloor = template.Templates.get(.@"builtin/functions/divFloor");
            const multiplier = try divFloor.module(T).structure.solve(&.{ .function = .{
                .name = "divFloor",
                .arguments = @constCast(&[_]*const Expression(T){ a, b }),
                .body = null,
            } }, Bindings(divFloor.key, T).init(.{
                .a = a,
                .b = b,
            }), allocator);

            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try (Expression(T){ .number = b.number * multiplier.steps[multiplier.steps.len - 1].after.number }).clone(allocator),
                try allocator.dupe(u8, "Calculate the whole part"),
                multiplier.steps,
                allocator,
            );

            // TODO extract the "negative" case into a different variant, and handle this subtraction accordingly (+1 step, or simply have it as a substep)
            const subtraction = template.Templates.get(.@"core/number/subtraction");
            const result = try subtraction.module(T).structure.solve(&.{
                .binary = .{
                    .left = a,
                    .right = solution.steps[0].after,
                    .operation = .subtraction,
                },
            }, Bindings(subtraction.key, T).init(.{
                .a = a,
                .b = solution.steps[0].after,
            }), allocator);

            solution.steps[1] = result.steps[0];
            allocator.free(result.steps);

            return solution;
        }
    };

    return Template(Key, T){ .structure = .{
        .name = "Number division remainder",
        .ast = Expression(T){
            .binary = .{
                .left = &.{ .templated = .number },
                .right = &.{ .templated = .number },
                .operation = .modulus,
            },
        },
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

test modulus {
    inline for (.{ f32, f64, f128 }) |T| {
        const Modulus = modulus(T);

        const ten_mod_four = testingData(T).get("10 % 4").?;

        const bindings = try Modulus.structure.matches(ten_mod_four);
        const solution = try Modulus.structure.solve(ten_mod_four, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = ten_mod_four,
                    .after = &.{ .number = 8.0 },
                    .description = "Calculate the whole part",
                    .substeps = @constCast(&[_]*const Step(T){
                        &.{
                            .before = &.{ .number = 1.0 },
                            .after = &.{ .number = 1.0 },
                            .description = "Figure out the magnitude of the result",
                            .substeps = @constCast(&[_]*const Step(T){
                                &.{
                                    .before = &.{ .binary = .{
                                        .left = &.{ .number = 4.0 },
                                        .right = &.{ .number = 1.0 },
                                        .operation = .multiplication,
                                    } },
                                    .after = &.{ .number = 4.0 },
                                    .description = "Since 4 is less than or equal to 10, we add 1 decimal place to our multiplier",
                                    .substeps = &.{},
                                },
                                &.{
                                    .before = &.{ .binary = .{
                                        .left = &.{ .number = 4.0 },
                                        .right = &.{ .number = 10.0 },
                                        .operation = .multiplication,
                                    } },
                                    .after = &.{ .number = 4.0 },
                                    .description = "Since 40 is more than 10, divide the multiplier by 10",
                                    .substeps = &.{},
                                },
                            }),
                        },
                        &.{
                            .before = &.{ .number = 1.0 },
                            .after = &.{ .number = 2.0 },
                            .description = "Refine the search",
                            .substeps = @constCast(&[_]*const Step(T){
                                &.{
                                    .before = &.{ .binary = .{
                                        .operation = .multiplication,
                                        .left = &.{ .number = 4.0 },
                                        .right = &.{ .function = .{
                                            .name = "add",
                                            .arguments = @constCast(&[_]*const Expression(T){
                                                &.{ .number = 1.0 },
                                                &.{ .number = 1.0 },
                                            }),
                                            .body = null,
                                        } },
                                    } },
                                    .after = &.{ .number = 8.0 },
                                    .description = "Since 8 is less than or equal to 10, we add one more magnitude to our multiplier",
                                    .substeps = &.{},
                                },
                                &.{
                                    .before = &.{ .binary = .{
                                        .operation = .multiplication,
                                        .left = &.{ .number = 4.0 },
                                        .right = &.{ .function = .{
                                            .name = "add",
                                            .arguments = @constCast(&[_]*const Expression(T){
                                                &.{ .number = 1.0 }, &.{ .binary = .{
                                                    .operation = .multiplication,
                                                    .left = &.{ .number = 1.0 },
                                                    .right = &.{ .binary = .{
                                                        .operation = .subtraction,
                                                        .left = &.{ .number = 2.0 },
                                                        .right = &.{ .number = 1.0 },
                                                    } },
                                                } },
                                            }),
                                            .body = null,
                                        } },
                                    } },
                                    .after = &.{ .number = 8.0 },
                                    .description = "Since 12 is more than 10, we go back to the previous multiplier and since the magnitude is equal to 1, we found the answer.",
                                    .substeps = &.{},
                                },
                            }),
                        },
                    }),
                },
                &.{
                    .before = &.{
                        .binary = .{
                            .left = &.{ .number = 10.0 },
                            .right = &.{ .number = 8.0 },
                            .operation = .subtraction,
                        },
                    },
                    .after = &.{ .number = 2.0 },
                    .description = "Subtract 8 from 10",
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
const Template = template.Template;
const Variant = template.Variant;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
