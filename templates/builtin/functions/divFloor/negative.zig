pub fn TestingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{});
}

const Key = template.Templates.get(.@"builtin/functions/divFloor").key;

pub fn negative(comptime T: type) Variant(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            const arguments = expression.function.arguments;

            // e.g. -5, 3 -> true != false, which is true; we only need one number to be negative. (because -a/-b = a/b)
            if ((arguments[0].number < 0.0) != (arguments[1].number < 0.0)) return Bindings(Key, T).init(.{
                .a = arguments[0],
                .b = arguments[1],
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            _ = expression;

            const divFloor = template.Templates.get(.@"builtin/functions/divFloor").module(T);
            const a = bindings.get(.a).?.number;
            const b = bindings.get(.b).?.number;

            const division = try divFloor.structure.solve(
                &.{
                    .function = .{
                        .name = "divFloor",
                        .arguments = @constCast(&[_]*const Expression(T){
                            &.{ .number = @abs(a) },
                            &.{ .number = @abs(b) },
                        }),
                        .body = null,
                    },
                },
                Bindings(Key, T).init(.{
                    .a = &.{ .number = @abs(a) },
                    .b = &.{ .number = @abs(b) },
                }),
                allocator,
            );

            const last = division.steps[division.steps.len - 1].after.?;
            const x = last.number;
            const remainder = (x + 1) * b - a;

            const solution = try Solution(T).init(division.steps.len + 1, allocator);
            @memcpy(solution.steps[0..division.steps.len], division.steps);

            solution.steps[solution.steps.len - 1] = try (Step(T){
                .before = try last.clone(allocator),
                .after = try (Expression(T){ .number = -last.number - 1 }).clone(allocator),
                .description = try std.fmt.allocPrint(allocator, "Since our original input contained negative numbers, we also have to change the sign of our result and also subtract one.\n\nThis is because $-{d} \\times {d} + {d}$ (the remainder) $= -{d} + {d} = -{d}$", .{ x + 1, b, remainder, (x + 1) * b, remainder, a }),
                .substeps = &.{},
            }).clone(allocator);

            return solution;
        }
    };

    // MARK: variant
    return Variant(Key, T){
        .name = "Builtin function: number division, rounded down: negative parameters",
        .matches = Impl.matches,
        .solve = Impl.solve,
        .score = 50,
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
