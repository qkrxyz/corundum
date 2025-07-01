pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1 + 2", &Expression(T){ .binary = .{
                .operation = .addition,
                .left = &.{ .number = 1.0 },
                .right = &.{ .number = 2.0 },
            } },
        },
    });
}

pub const Key = enum {
    a,
    b,
};

pub fn addition(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            var bindings = Bindings(Key, T).init(.{});

            bindings.put(.a, expression.binary.left);
            bindings.put(.b, expression.binary.right);

            return bindings;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), context: Context(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            @setFloatMode(.optimized);

            if (try context.find_variants(.@"core/number/addition", expression, allocator)) |solution| return solution;

            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const solution = try Solution(T).init(1, true, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try (Expression(T){ .number = a + b }).clone(allocator),
                try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ a, b }),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .structure = .{
            .name = "Number addition",
            .ast = Expression(T){
                .binary = .{
                    .operation = .addition,
                    .left = &Expression(T){ .templated = .number },
                    .right = &Expression(T){ .templated = .number },
                },
            },
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

// MARK: tests
test addition {
    const Addition = addition(f64);
    const one_plus_two = Expression(f64){ .binary = .{
        .operation = .addition,
        .left = &.{ .number = 1.0 },
        .right = &.{ .number = 2.0 },
    } };

    try testing.expect(Addition.structure.ast.structural() == one_plus_two.structural());
}

test "addition(T).matches" {
    const Addition = addition(f64);

    const one_plus_two = testingData(f64).get("1 + 2").?;

    const bindings = try Addition.structure.matches(one_plus_two);
    try testing.expectEqualDeep(bindings.get(.a), one_plus_two.binary.left);
    try testing.expectEqualDeep(bindings.get(.b), one_plus_two.binary.right);
}

test "addition(T).solve" {
    const Addition = addition(f64);

    const one_plus_two = testingData(f64).get("1 + 2").?;

    const bindings = try Addition.structure.matches(one_plus_two);
    const solution = try Addition.structure.solve(one_plus_two, bindings, .default, testing.allocator);
    defer solution.deinit(testing.allocator);

    const expected = Solution(f64){
        .is_final = true,
        .steps = @constCast(&[_]*const Step(f64){
            &.{
                .before = one_plus_two,
                .after = &.{ .number = 3.0 },
                .description = "Add 1 and 2 together",
                .substeps = &.{},
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
