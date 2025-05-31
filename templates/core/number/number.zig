pub fn number(comptime T: type) Template(T) {
    return Template(T){
        .structure = .{
            .name = "Number",
            .ast = Expression(T){ .templated = .number },
            .matches = struct {
                fn matches(expression: *const Expression(T), allocator: std.mem.Allocator) anyerror!Bindings(T) {
                    if (std.math.isNan(expression.number)) {
                        return error.NotANumber;
                    }

                    if (std.math.isInf(expression.number)) {
                        return error.Infinity;
                    }

                    var bindings = Bindings(T).init(allocator);
                    try bindings.put("x", expression);

                    return bindings;
                }
            }.matches,
            .solve = struct {
                fn solve(expression: *const Expression(T), bindings: Bindings(T), allocator: std.mem.Allocator) anyerror!Solution(T) {
                    const steps = try allocator.alloc(Step(T), 1);
                    steps[0] = Step(T){
                        .before = try expression.clone(allocator),
                        .after = try expression.clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "{d} is a number.", .{bindings.get("x").?.number}),
                        .substeps = &.{},
                    };

                    return Solution(T){
                        .steps = steps,
                    };
                }
            }.solve,
        },
    };
}

test number {
    const Number = number(f64);
    const one = Expression(f64){ .number = 1.0 };

    try testing.expect(Number.structure.ast.structural() == one.structural());
}

test "number(T).matches" {
    const Number = number(f64);

    const one = Expression(f64){ .number = 1.0 };
    const two = Expression(f64){ .number = 2.0 };

    var bindings = try Number.structure.matches(&one, testing.allocator);
    defer bindings.deinit();

    try testing.expectEqual(bindings.get("x"), &one);
    bindings.deinit();

    bindings = try Number.structure.matches(&two, testing.allocator);
    try testing.expectEqual(bindings.get("x"), &two);
}

test "number(T).matches - edge cases" {
    const Number = number(f64);

    const inf = Expression(f64){ .number = std.math.inf(f64) };
    const negative_inf = Expression(f64){ .number = -inf.number };
    const nan = Expression(f64){ .number = std.math.nan(f64) };
    const signaling_nan = Expression(f64){ .number = std.math.snan(f64) };

    try testing.expectError(error.Infinity, Number.structure.matches(&inf, testing.allocator));
    try testing.expectError(error.Infinity, Number.structure.matches(&negative_inf, testing.allocator));
    try testing.expectError(error.NotANumber, Number.structure.matches(&nan, testing.allocator));
    try testing.expectError(error.NotANumber, Number.structure.matches(&signaling_nan, testing.allocator));
}

test "number(T).solve" {
    const Number = number(f64);

    const one = Expression(f64){ .number = 1.0 };

    var bindings = try Number.structure.matches(&one, testing.allocator);
    defer bindings.deinit();

    const solution = try Number.structure.solve(&one, bindings, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected: Solution(f64) = Solution(f64){
        .steps = @constCast(&[_]Step(f64){
            .{
                .before = &.{ .number = 1.0 },
                .after = &.{ .number = 1.0 },
                .description = "1 is a number.",
                .substeps = &[0]*Step(f64){},
            },
        }),
    };

    try testing.expectEqualDeep(expected, solution);
}

const std = @import("std");
const testing = std.testing;

const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
