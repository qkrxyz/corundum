pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{
        .{
            "1 + 3 + 2", &Expression(T){ .function = .{
                .name = "add",
                .arguments = @constCast(&[_]*const Expression(T){
                    &.{ .number = 1.0 },
                    &.{ .number = 3.0 },
                    &.{ .number = 2.0 },
                }),
                .body = null,
            } },
        },
    });
}

pub const Key = enum {};

pub fn sum(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T), allocator: std.mem.Allocator) anyerror![]*const Expression(T) {
            if (expression.* != .function) return error.NotApplicable;
            if (!std.mem.eql(u8, expression.function.name, "add")) return error.WrongFunctionSignature;
            if (expression.function.arguments.len < 2) return error.NotEnoughArguments;

            for (expression.function.arguments) |argument| {
                if (argument.* != .number) return error.NotANumber;
            }

            const bindings = try allocator.alloc(*const Expression(T), expression.function.arguments.len);
            @memcpy(bindings, expression.function.arguments);
            return bindings;
        }

        // MARK: .solve()
        // TODO call @"core/number/addition" so that the identities are handled correctly
        fn solve(expression: *const Expression(T), bindings: []*const Expression(T), allocator: std.mem.Allocator) std.mem.Allocator.Error!Solution(T) {
            @setFloatMode(.optimized);

            const solution = try Solution(T).init(bindings.len - 1, true, allocator);

            const initial_args = blk: {
                var arguments = try std.ArrayList(*const Expression(T)).initCapacity(allocator, 2);

                try arguments.append(&Expression(T){ .number = bindings[0].number + bindings[1].number });
                try arguments.appendSlice(if (bindings.len >= 3) bindings[2..] else &.{});

                break :blk try arguments.toOwnedSlice();
            };
            defer allocator.free(initial_args);

            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try (Expression(T){ .function = .{
                    .name = "add",
                    .arguments = initial_args,
                    .body = null,
                } }).clone(allocator),
                try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ bindings[0].number, bindings[1].number }),
                &.{},
                allocator,
            );

            if (bindings.len == 2) return solution;

            for (bindings[2..], 2..) |x, i| {
                const last = solution.steps[i - 2];
                const result = last.after.function.arguments[0].number + x.number;

                if (i == bindings.len - 1) {
                    solution.steps[i - 1] = try Step(T).init(
                        try last.after.clone(allocator),
                        try (Expression(T){ .number = result }).clone(allocator),
                        try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ last.after.function.arguments[0].number, x.number }),
                        &.{},
                        allocator,
                    );

                    break;
                }

                const new_args = blk: {
                    var arguments = try std.ArrayList(*const Expression(T)).initCapacity(allocator, 1 + (bindings.len - i));

                    try arguments.append(&Expression(T){ .number = result });
                    if (bindings.len >= i + 1) try arguments.appendSlice(bindings[i + 1 ..]);

                    break :blk try arguments.toOwnedSlice();
                };
                defer allocator.free(new_args);

                solution.steps[i - 1] = try Step(T).init(
                    try last.after.clone(allocator),
                    try (Expression(T){ .function = .{
                        .name = "add",
                        .arguments = new_args,
                        .body = null,
                    } }).clone(allocator),
                    try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ last.after.function.arguments[0].number, x.number }),
                    &.{},
                    allocator,
                );
            }

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .@"n-ary" = .{
            .name = "N-ary function: sum of numbers",
            .matches = Impl.matches,
            .solve = Impl.solve,
        },
    };
}

// MARK: tests
test sum {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = sum(T);

        const one_three_two = testingData(T).kvs.values[0];

        const bindings = try Addition.@"n-ary".matches(one_three_two, testing.allocator);
        defer testing.allocator.free(bindings);

        const expected: []*const Expression(T) = @constCast(&[_]*const Expression(T){
            &.{ .number = 1.0 },
            &.{ .number = 3.0 },
            &.{ .number = 2.0 },
        });

        try testing.expectEqualDeep(expected, bindings);
    }
}

test "sum(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = sum(T);

        const one_three_two = testingData(T).get("1 + 3 + 2").?;

        const bindings = try Addition.@"n-ary".matches(one_three_two, testing.allocator);
        defer testing.allocator.free(bindings);

        const solution = try Addition.@"n-ary".solve(one_three_two, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){
            .is_final = true,
            .steps = @constCast(&[_]*const Step(T){
                &.{
                    .before = &.{ .function = .{
                        .name = "add",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{ .number = 1.0 },
                            &.{ .number = 3.0 },
                            &.{ .number = 2.0 },
                        }),
                        .body = null,
                    } },
                    .after = &.{ .function = .{
                        .name = "add",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{ .number = 4.0 },
                            &.{ .number = 2.0 },
                        }),
                        .body = null,
                    } },
                    .description = "Add 1 and 3 together",
                    .substeps = &.{},
                },
                &.{
                    .before = &.{ .function = .{
                        .name = "add",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{ .number = 4.0 },
                            &.{ .number = 2.0 },
                        }),
                        .body = null,
                    } },
                    .after = &.{ .number = 6.0 },
                    .description = "Add 4 and 2 together",
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
