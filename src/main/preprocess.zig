pub fn preprocess(
    input: [:0]const u8,
    allocator: std.mem.Allocator,
    rdtsc: fn () callconv(.@"inline") u64,
    frequency: fn () callconv(.@"inline") u64,
    comptime iterations: comptime_int,
) !void {
    var progress = std.Progress.start(.{ .estimated_total_items = iterations, .root_name = "Preprocessing..." });

    var times: []u64 = try allocator.alloc(u64, iterations);
    defer allocator.free(times);

    var cycles: []u64 = try allocator.alloc(u64, iterations);
    defer allocator.free(cycles);

    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        const cycles_start = rdtsc();

        var parser = corundum.parser.Parser(f64).init(input, allocator);
        try parser.preprocess();
        parser.deinit();

        const cycles_end = rdtsc();
        const took = timer.read();

        times[i] = took;
        cycles[i] = cycles_end - cycles_start;

        progress.completeOne();
    }

    progress.end();

    // sort
    std.mem.sort(u64, times, {}, std.sort.asc(u64));

    // outliers
    const q1 = times[iterations / 4];
    const q3 = times[iterations * 3 / 4];

    const iqr = q3 - q1;

    const lower = q1 - (iqr * 3 / 2);
    const higher = q3 + (iqr * 3 / 2);

    const filtered = blk: {
        var i: usize = 0;
        for (times) |time| {
            if (time >= lower) break;
            i += 1;
        }
        const lower_idx = i;

        i = 0;
        for (times) |time| {
            if (time >= higher) break;
            i += 1;
        }
        const higher_idx = i;

        const result = times[lower_idx..higher_idx];

        if (result.len == 0) break :blk times;
        break :blk result;
    };

    var sum: u64 = 0;
    for (filtered) |value| {
        sum += value;
    }

    const average = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(filtered.len));

    // std deviation
    var variance_sum: f64 = 0.0;
    for (filtered) |time| {
        const diff = @as(f64, @floatFromInt(time)) - average;
        variance_sum += diff * diff;
    }
    const variance = variance_sum / @as(f64, @floatFromInt(filtered.len));
    const std_deviation = @sqrt(variance);

    // cycles
    var cycles_sum: u64 = 0;
    for (cycles) |x| cycles_sum += x;

    const freq = frequency();

    const average_cycles: ?f128 = if (builtin.target.cpu.arch.isX86() or builtin.target.cpu.arch.isAARCH64()) @as(f128, @floatFromInt(cycles_sum)) / iterations else null;

    std.debug.print("[{d} iterations] {d:.2} ± {d:.2} ns ({d} outliers)", .{
        iterations,
        average,
        std_deviation,
        iterations - filtered.len,
    });

    if (average_cycles) |c| {
        std.debug.print(", average {d:.2} {s}/iter", .{
            c,
            if (builtin.target.cpu.arch.isX86()) "cycles" else "ticks",
        });

        if (builtin.target.cpu.arch.isAARCH64()) {
            std.debug.print(" (frequency: {d} Hz, 1 tick = {d:.1} ns)", .{ freq, (1.0 / @as(f128, @floatFromInt(freq))) * std.time.ns_per_s });
        }
    }

    var parser = corundum.parser.Parser(f64).init(input, allocator);
    defer parser.deinit();

    try parser.preprocess();

    std.debug.print("\nactual output: `{s}`\n", .{parser.buffer.items});

    return;
}

const std = @import("std");
const corundum = @import("corundum");
const builtin = @import("builtin");
