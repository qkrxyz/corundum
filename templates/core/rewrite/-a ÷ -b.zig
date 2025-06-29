pub fn testingData(comptime T: type) std.StaticStringMap(*const Expression(T)) {
    return .initComptime(.{});
}

pub const Key = enum {
    a,
    b,
};

pub fn @"-a ÷ -b"(comptime T: type) Template(Key, T) {
    const Impl = struct {
        // MARK: .matches()
        fn matches(expression: *const Expression(T)) anyerror!Bindings(Key, T) {
            if (expression.* != .binary) return error.NotApplicable;
            if (expression.binary.operation != .division) return error.NotApplicable;

            const left = (expression.binary.left.* == .number and expression.binary.left.number < 0.0) or (expression.binary.left.* == .unary and expression.binary.left.unary.operation == .negation);
            const right = (expression.binary.right.* == .number and expression.binary.right.number < 0.0) or (expression.binary.right.* == .unary and expression.binary.right.unary.operation == .negation);

            if (left and right) return Bindings(Key, T).init(.{
                .a = expression.binary.left,
                .b = expression.binary.right,
            });

            return error.NotApplicable;
        }

        // MARK: .solve()
        fn solve(expression: *const Expression(T), bindings: Bindings(Key, T), allocator: std.mem.Allocator) anyerror!Solution(T) {
            const a = switch (bindings.get(.a).?.*) {
                .number => bindings.get(.a).?,
                .unary => |unary| unary.operand,
                else => unreachable,
            };

            const b = switch (bindings.get(.b).?.*) {
                .number => bindings.get(.b).?,
                .unary => |unary| unary.operand,
                else => unreachable,
            };

            const solution = try Solution(T).init(1, false, allocator);
            solution.steps[0] = try Step(T).init(
                try expression.clone(allocator),
                try Expression(T).init(.{
                    .binary = .{
                        .left = a,
                        .right = b,
                        .operation = .division,
                    },
                }, allocator),
                try allocator.dupe(u8, "Two minus signs give a plus sign"),
                &.{},
                allocator,
            );

            return solution;
        }
    };

    // MARK: template
    return Template(Key, T){
        .dynamic = .{
            .name = "Division: -a ÷ -b",
            .matches = Impl.matches,
            .solve = Impl.solve,
            .variants = &.{},
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
