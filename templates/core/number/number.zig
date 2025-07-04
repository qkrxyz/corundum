pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1", &Expression(T){ .number = 1.0 },
        },
    });
}

pub const Key = enum {
    x,
};

pub fn number(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const bindings = Bindings(Key, T).init(.{ .x = expression });
            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            _ = context;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try expression.clone(allocator),
                try std.fmt.allocPrint(allocator, "{d} is a number.", .{bindings.get(.x).?.number}),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .structure = .{
            .name = "Number",
            .ast = Expression(T){ .templated = .number },
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

// MARK: tests
test number {
    const Number = number(f64);
    const one = testingData(f64).get("1").?;

    try testing.expect(Number.structure.ast.structural() == one.structural());
}

test "number(T).matches" {
    const Number = number(f64);

    const one = testingData(f64).kvs.values[0];

    const bindings = try Number.structure.matches(one);
    try testing.expectEqual(bindings.get(.x), one);
}

test "number(T).solve" {
    const Number = number(f64);

    const one = testingData(f64).get("1").?;

    const bindings = try Number.structure.matches(one);

    const solution = try Number.structure.solve(one, bindings, .default, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected: Solution(f64) = Solution(f64){
        .is_final = true,
        .steps = @constCast(&[_]*const Step(f64){
            &.{
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
const engine = @import("engine");

const Context = engine.Context;
const Expression = expr.Expression;
const Template = template.Template;
const Solution = template.Solution;
const Step = template.Step;
const Bindings = template.Bindings;
