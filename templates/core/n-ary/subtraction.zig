pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{});
}

pub const Key = usize;

pub fn subtraction(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .count()
        fn count(expression: *const Expression(T)) anyerror!usize {
            switch (expression.*) {
                .binary => |binary| {
                    // [...] - (-x) = [...] + x
                    if (expression.binary.operation == .addition and expression.binary.right.* == .unary and expression.binary.right.unary.operation == .negation) {
                        return try count(binary.left) + 1;
                    }

                    if (expression.binary.operation != .subtraction) return error.NotApplicable;

                    return try count(binary.left) + try count(binary.right);
                },

                .number,
                .variable,
                .fraction,
                .parenthesis,
                .unary,
                .function,
                => return 1,

                .equation => return error.BinaryEquation,
                .boolean => return error.BooleanArithmetic,
                .templated => unreachable,
            }
        }

        // MARK: .impl()
        fn impl(expression: *const Expression(T), allocator: std.mem.Allocator, capacity: usize) anyerror!Bindings(Key, T) {
            var bindings = try std.ArrayList(*const Expression(T)).initCapacity(allocator, capacity);
            errdefer bindings.deinit();

            var i: usize = 0;

            switch (expression.*) {
                .binary => |binary| {
                    // [...] + (-x) = [...] - x
                    if (expression.binary.operation == .addition and expression.binary.right.* == .unary and expression.binary.right.unary.operation == .negation) {
                        const left = try impl(binary.left, allocator, capacity - 1);
                        defer allocator.free(left);

                        for (0..left.len) |j| {
                            try bindings.append(left[j]);
                            i += 1;
                        }

                        try bindings.append(expression.binary.right.unary.operand);
                        return bindings.toOwnedSlice();
                    }

                    if (expression.binary.operation != .subtraction) return error.NotApplicable;

                    const left = try impl(binary.left, allocator, 1);
                    defer allocator.free(left);

                    const right = try impl(binary.right, allocator, 1);
                    defer allocator.free(right);

                    for (0..left.len) |j| {
                        try bindings.append(left[j]);
                        i += 1;
                    }

                    for (0..right.len) |j| {
                        try bindings.append(right[j]);
                        i += 1;
                    }
                },

                .number,
                .variable,
                .fraction,
                .parenthesis,
                .unary,
                .function,
                => try bindings.append(expression),

                .equation => return error.BinaryEquation,
                .boolean => return error.BooleanArithmetic,
                .templated => unreachable,
            }

            return bindings.toOwnedSlice();
        }

        // MARK: .matches()
        fn matches(expression: *const Expression(T), allocator: std.mem.Allocator) anyerror!Bindings(Key, T) {
            if (expression.* != .binary) return error.NotApplicable;

            const capacity = try count(expression);
            if (capacity < 2) return error.NotEnoughParameters;

            return impl(expression, allocator, capacity);
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            const solution = try Solution(T).init(1, false, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{ .function = .{
                    .name = "sub",
                    .arguments = bindings,
                    .body = null,
                } }, allocator),
                try allocator.dupe(u8, ""),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){ .dynamic = .{
        .name = "N-ary function: subtraction",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

// MARK: tests
test subtraction {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = subtraction(T);

        const one_three_two = Expression(T){ .binary = .{
            .left = &.{
                .binary = .{
                    .left = &.{ .number = 1.0 },
                    .right = &.{ .number = 3.0 },
                    .operation = .subtraction,
                },
            },
            .right = &.{ .number = 2.0 },
            .operation = .subtraction,
        } };

        const bindings = try Addition.dynamic.matches(&one_three_two, testing.allocator);
        defer testing.allocator.free(bindings);

        const expected: []*const Expression(T) = @constCast(&[_]*const Expression(T){
            &.{ .number = 1.0 },
            &.{ .number = 3.0 },
            &.{ .number = 2.0 },
        });

        try testing.expectEqualDeep(expected, bindings);
    }
}

test "subtraction(T).matches(number, variable, fraction)" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Subtraction = subtraction(T);

        const one_x_pi_2 = Expression(T){
            .binary = .{
                .left = &.{
                    .binary = .{
                        .left = &.{ .number = 1.0 },
                        .right = &.{ .variable = "x" },
                        .operation = .subtraction,
                    },
                },
                .right = &.{
                    .fraction = .{
                        .numerator = &.{ .variable = "pi" },
                        .denominator = &.{ .number = 2.0 },
                    },
                },
                .operation = .subtraction,
            },
        };

        const bindings = try Subtraction.dynamic.matches(&one_x_pi_2, testing.allocator);
        defer testing.allocator.free(bindings);

        const expected: []*const Expression(T) = @constCast(&[_]*const Expression(T){
            &.{ .number = 1.0 },
            &.{ .variable = "x" },
            &.{ .fraction = .{
                .numerator = &.{ .variable = "pi" },
                .denominator = &.{ .number = 2.0 },
            } },
        });

        try testing.expectEqualDeep(expected, bindings);
    }
}

test "subtraction(T).matches(..., equation)" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Subtraction = subtraction(T);

        const one_x_eql_1 = Expression(T){
            .binary = .{
                .left = &.{ .number = 1.0 },
                .right = &.{
                    .equation = .{
                        .left = &.{ .variable = "x" },
                        .right = &.{ .number = 1.0 },
                        .sign = .equals,
                    },
                },
                .operation = .subtraction,
            },
        };

        const bindings = Subtraction.dynamic.matches(&one_x_eql_1, testing.allocator);
        try testing.expectError(error.BinaryEquation, bindings);
    }
}

test "Subtraction(T).matches(..., boolean)" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Subtraction = subtraction(T);

        const one_bool = Expression(T){
            .binary = .{
                .left = &.{ .number = 1.0 },
                .right = &.{ .boolean = true },
                .operation = .subtraction,
            },
        };

        const bindings = Subtraction.dynamic.matches(&one_bool, testing.allocator);
        try testing.expectError(error.BooleanArithmetic, bindings);
    }
}

test "subtraction(T).matches(..., unary)" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Subtraction = subtraction(T);

        const one_three_negative_x = Expression(T){ .binary = .{
            .left = &.{
                .binary = .{
                    .left = &.{ .number = 1.0 },
                    .right = &.{ .number = 3.0 },
                    .operation = .subtraction,
                },
            },
            .right = &.{
                .unary = .{
                    .operation = .negation,
                    .operand = &.{ .variable = "x" },
                },
            },
            .operation = .addition,
        } };

        const bindings = try Subtraction.dynamic.matches(&one_three_negative_x, testing.allocator);
        defer testing.allocator.free(bindings);

        const expected: []*const Expression(T) = @constCast(&[_]*const Expression(T){
            &.{ .number = 1.0 },
            &.{ .number = 3.0 },
            &.{ .variable = "x" },
        });

        try testing.expectEqualDeep(expected, bindings);
    }
}

test "subtraction(T).matches(...) - not enough parameters/wrong structure" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Subtraction = subtraction(T);

        const one = Expression(T){ .number = 3.14 };

        const bindings = Subtraction.dynamic.matches(&one, testing.allocator);
        try testing.expectError(error.NotApplicable, bindings);
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
