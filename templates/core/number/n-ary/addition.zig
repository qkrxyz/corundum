pub const Key = usize;

pub fn addition(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T), allocator: std.mem.Allocator) anyerror!Bindings(Key, T) {
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
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            var steps = std.ArrayList(*const Step(T)).init(allocator);

            const initial_args = blk: {
                var arguments = std.ArrayList(*const Expression(T)).init(allocator);

                try arguments.append(&Expression(T){ .number = bindings[0].number + bindings[1].number });
                try arguments.appendSlice(if (bindings.len >= 3) bindings[2..] else &.{});

                break :blk try arguments.toOwnedSlice();
            };
            defer allocator.free(initial_args);

            try steps.append(try (Step(T){
                .before = try expression.clone(allocator),
                .after = try (Expression(T){ .function = .{
                    .name = "add",
                    .arguments = initial_args,
                    .body = null,
                } }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ bindings[0].number, bindings[1].number }),
                .substeps = &.{},
            }).clone(allocator));

            if (bindings.len == 2) return Solution(T){ .steps = try steps.toOwnedSlice() };

            for (bindings[2..], 2..) |x, i| {
                const last = steps.getLast();
                const result = last.after.?.function.arguments[0].number + x.number;

                if (i == bindings.len - 1) {
                    try steps.append(try (Step(T){
                        .before = try last.after.?.clone(allocator),
                        .after = try (Expression(T){ .number = result }).clone(allocator),
                        .description = try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ last.after.?.function.arguments[0].number, x.number }),
                        .substeps = &.{},
                    }).clone(allocator));

                    break;
                }

                const new_args = blk: {
                    var arguments = std.ArrayList(*const Expression(T)).init(allocator);

                    try arguments.append(&Expression(T){ .number = result });
                    if (bindings.len >= i + 1) try arguments.appendSlice(bindings[i + 1 ..]);

                    break :blk try arguments.toOwnedSlice();
                };
                defer allocator.free(new_args);

                try steps.append(try (Step(T){
                    .before = try last.after.?.clone(allocator),
                    .after = try (Expression(T){ .function = .{
                        .name = "add",
                        .arguments = new_args,
                        .body = null,
                    } }).clone(allocator),
                    .description = try std.fmt.allocPrint(allocator, "Add {d} and {d} together", .{ last.after.?.function.arguments[0].number, x.number }),
                    .substeps = &.{},
                }).clone(allocator));
            }

            return Solution(T){ .steps = try steps.toOwnedSlice() };
        }
    };

    // MARK: template
    return Template(Key, T){ .dynamic = .{
        .name = "N-ary function: number addition",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .variants = &.{},
    } };
}

// MARK: tests
test addition {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = addition(T);

        const one_three_two = Expression(T){ .function = .{
            .name = "add",
            .arguments = @constCast(&[_]*const Expression(T){
                &.{ .number = 1.0 },
                &.{ .number = 3.0 },
                &.{ .number = 2.0 },
            }),
            .body = null,
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

test "addition(T).solve" {
    inline for (.{ f32, f64, f128 }) |T| {
        const Addition = addition(T);

        const one_three_two = Expression(T){ .function = .{
            .name = "add",
            .arguments = @constCast(&[_]*const Expression(T){
                &.{ .number = 1.0 },
                &.{ .number = 3.0 },
                &.{ .number = 2.0 },
            }),
            .body = null,
        } };

        const bindings = try Addition.dynamic.matches(&one_three_two, testing.allocator);
        defer testing.allocator.free(bindings);

        const solution = try Addition.dynamic.solve(&one_three_two, bindings, testing.allocator);
        defer solution.deinit(testing.allocator);

        const expected = Solution(T){ .steps = @constCast(&[_]*const Step(T){
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
        }) };

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
