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
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const allocator = arena.allocator();

    // benchmarks
    const ITERATIONS = 10000;
    var progress = std.Progress.start(.{ .estimated_total_items = ITERATIONS, .root_name = "Running benchmarks..." });

    var results: [ITERATIONS]u64 = undefined;
    for (0..ITERATIONS) |i| {
        var timer = try std.time.Timer.start();

        try benchmark(allocator, 2.5, 3.5);

        results[i] = timer.read();
        progress.completeOne();
    }

    progress.end();

    // average
    var sum: u64 = 0;
    for (results) |value| {
        sum += value;
    }

    const average = sum / ITERATIONS;

    // mean
    std.mem.sort(u64, &results, {}, std.sort.asc(u64));
    const mean = results[ITERATIONS / 2];

    // std deviation
    var variance_sum: f64 = 0.0;
    for (results) |time| {
        const diff = @as(f64, @floatFromInt(time)) - @as(f64, @floatFromInt(average));
        variance_sum += diff * diff;
    }
    const variance = variance_sum / ITERATIONS;
    const std_deviation = @sqrt(variance);

    std.debug.print("\x1b[1mmean ± σ\x1b[0m\n", .{});
    printTime(@as(f64, @floatFromInt(mean)));
    std.debug.print(" ± ", .{});
    printTime(std_deviation);
    std.debug.print("\n", .{});
}

fn printTime(nanoseconds: f64) void {
    if (nanoseconds < 1000) {
        std.debug.print("{d:.2} ns", .{nanoseconds});
    } else if (nanoseconds < 1_000_000) {
        std.debug.print("{d:.2} μs", .{nanoseconds / 1000.0});
    } else if (nanoseconds < 1_000_000_000) {
        std.debug.print("{d:.2} ms", .{nanoseconds / 1_000_000.0});
    } else {
        std.debug.print("{d:.2} s", .{nanoseconds / 1_000_000_000.0});
    }
}

fn benchmark(allocator: std.mem.Allocator, a: f64, b: f64) !void {
    @setFloatMode(.optimized);

    const multiplication = corundum.template.Templates.get(.@"core/number/multiplication");
    const bindings = try multiplication.module(f64).structure.matches(&corundum.expr.Expression(f64){
        .binary = .{
            .operation = .multiplication,
            .left = &.{ .number = a },
            .right = &.{ .number = b },
        },
    });
    // std.debug.print("bindings: {any}\n", .{bindings});

    const solution = try multiplication.module(f64).structure.solve(&corundum.expr.Expression(f64){
        .binary = .{
            .operation = .multiplication,
            .left = &.{ .number = a },
            .right = &.{ .number = b },
        },
    }, bindings, allocator);
    defer solution.deinit(allocator);
}
