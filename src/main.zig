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

    var numbers: [2]f128 = undefined;
    var i: usize = 0;

    _ = arguments.skip();
    while (arguments.next()) |value| {
        numbers[i] = try std.fmt.parseFloat(f128, value);
        i += 1;
    }

    std.debug.print("addition\n-----\n", .{});
    {
        const addition = corundum.template.Templates.get(.@"core/number/addition").module(f128);
        const bindings = try addition.structure.matches(&corundum.expr.Expression(f128){
            .binary = .{
                .operation = .addition,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        });
        std.debug.print("bindings: {any}\n", .{bindings});

        const solution = try addition.structure.solve(&corundum.expr.Expression(f128){
            .binary = .{
                .operation = .addition,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        }, bindings, gpa);
        defer solution.deinit(gpa);

        std.debug.print("solution:\n", .{});

        const stderr = std.io.getStdErr().writer();
        try std.zon.stringify.serializeArbitraryDepth(solution, .{}, stderr);
    }

    std.debug.print("\n\nsubtraction\n-----\n", .{});
    {
        const subtraction = corundum.template.Templates.get(.@"core/number/subtraction").module(f128);
        const bindings = try subtraction.structure.matches(&corundum.expr.Expression(f128){
            .binary = .{
                .operation = .subtraction,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        });
        std.debug.print("bindings: {any}\n", .{bindings});

        const solution = try subtraction.structure.solve(&corundum.expr.Expression(f128){
            .binary = .{
                .operation = .subtraction,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        }, bindings, gpa);
        defer solution.deinit(gpa);

        const stderr = std.io.getStdErr().writer();
        try std.zon.stringify.serializeArbitraryDepth(solution, .{}, stderr);
    }

    std.debug.print("\n\nmultiplication\n-----\n", .{});
    {
        const multiplication = corundum.template.Templates.get(.@"core/number/multiplication");
        const bindings = try multiplication.module(f128).structure.matches(&corundum.expr.Expression(f128){
            .binary = .{
                .operation = .multiplication,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        });
        std.debug.print("bindings: {any}\n", .{bindings});

        const solution = try multiplication.module(f128).structure.solve(&corundum.expr.Expression(f128){
            .binary = .{
                .operation = .multiplication,
                .left = &.{ .number = numbers[0] },
                .right = &.{ .number = numbers[1] },
            },
        }, bindings, gpa);
        defer solution.deinit(gpa);

        const stderr = std.io.getStdErr().writer();
        try std.zon.stringify.serializeArbitraryDepth(solution.steps, .{}, stderr);
    }
}
