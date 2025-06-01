const builtin = @import("builtin");
const std = @import("std");
const corundum = @import("corundum");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa, const is_debug = gpa: {
        if (builtin.target.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var arguments = try std.process.argsWithAllocator(gpa);
    defer arguments.deinit();

    var numbers: [2]f64 = undefined;
    var i: usize = 0;

    _ = arguments.skip();
    while (arguments.next()) |value| {
        numbers[i] = try std.fmt.parseFloat(f64, value);
        i += 1;
    }

    std.debug.print("addition\n-----\n", .{});
    {
        const addition = corundum.template.Templates(f64).get("core/number/addition");
        const bindings = try addition.module.structure.matches(&corundum.expr.Expression(f64){
            .binary = .{
                .operation = .addition,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        });
        std.debug.print("bindings: {any}\n", .{bindings});

        const solution = try addition.module.structure.solve(&corundum.expr.Expression(f64){
            .binary = .{
                .operation = .addition,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        }, bindings, gpa);
        defer solution.deinit(gpa);

        std.debug.print("solution:\n", .{});
        for (solution.steps, 0..) |step, idx| {
            std.debug.print("{d}. '{s}' ({any} -> {any})\n", .{ idx, step.description, step.before, step.after });
        }
    }

    std.debug.print("\nsubtraction\n-----\n", .{});
    {
        const subtraction = corundum.template.Templates(f64).get("core/number/subtraction");
        const bindings = try subtraction.module.structure.matches(&corundum.expr.Expression(f64){
            .binary = .{
                .operation = .subtraction,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        });
        std.debug.print("bindings: {any}\n", .{bindings});

        const solution = try subtraction.module.structure.solve(&corundum.expr.Expression(f64){
            .binary = .{
                .operation = .subtraction,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        }, bindings, gpa);
        defer solution.deinit(gpa);

        std.debug.print("solution:\n", .{});
        for (solution.steps, 0..) |step, idx| {
            std.debug.print("{d}. '{s}' ({any} -> {any})\n", .{ idx, step.description, step.before, step.after });
        }
    }
}
