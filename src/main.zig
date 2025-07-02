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

    const arguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, arguments);

    if (arguments.len < 2) return;

    if (std.mem.eql(u8, "--preprocess", arguments[1])) {
        const perf = @import("perf.zig");

        const rdtsc = perf.rdtsc;
        const ITERATIONS = perf.ITERATIONS * 100;

        var progress = std.Progress.start(.{ .estimated_total_items = ITERATIONS, .root_name = "Preprocessing..." });

        var times: []u64 = try allocator.alloc(u64, ITERATIONS);
        defer allocator.free(times);

        var cycles: []usize = try allocator.alloc(usize, ITERATIONS);
        defer allocator.free(cycles);

        for (0..ITERATIONS) |i| {
            var timer = try std.time.Timer.start();

            const cycles_start = rdtsc();

            var parser = corundum.parser.Parser(f64).init(arguments[2], gpa);
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
        const q1 = times[ITERATIONS / 4];
        const q3 = times[ITERATIONS * 3 / 4];

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
        var cycles_sum: usize = 0;
        for (cycles) |x| cycles_sum += x;

        const frequency = perf.frequency();

        const average_cycles: ?usize = if (builtin.target.cpu.arch.isX86() or builtin.target.cpu.arch.isAARCH64()) cycles_sum / ITERATIONS else null;

        std.debug.print("[{d} iterations] {d:.2} ± {d:.2} ns ({d} outliers)", .{
            ITERATIONS,
            average,
            std_deviation,
            ITERATIONS - filtered.len,
        });

        if (average_cycles) |c| {
            std.debug.print(", average {d} {s}/iter", .{
                c,
                if (builtin.target.cpu.arch.isX86()) "cycles" else "ticks",
            });

            if (builtin.target.cpu.arch.isAARCH64()) {
                std.debug.print(" (frequency: {d} Hz, 1 tick = {d:.1} ns)", .{ frequency, (1.0 / @as(f128, @floatFromInt(frequency))) * std.time.ns_per_s });
            }
        }

        std.debug.print("\n", .{});

        var parser = corundum.parser.Parser(f64).init(arguments[2], gpa);
        try parser.preprocess();

        std.debug.print("actual output: `{s}`\n", .{parser.buffer.items});

        defer parser.deinit();

        return;
    }

    // var diagnostics: std.zon.parse.Diagnostics = .{};

    // const parsed = std.zon.parse.fromSlice(*const corundum.expr.Expression(f64), allocator, arguments[1], &diagnostics, .{}) catch {
    //     var error_iterator = diagnostics.iterateErrors();
    //     while (error_iterator.next()) |err| {
    //         const stderr = std.io.getStdErr().writer();
    //         try err.fmtMessage(&diagnostics).format("error: {s}\n", .{}, stderr);
    //     }

    //     std.process.exit(1);
    // };
    // defer parsed.deinit(allocator);

    // const structural = parsed.structural();
    // const hash = parsed.hash();

    // inline for (corundum.template.Templates.all()) |template| {
    //     const value = corundum.template.Templates.get(template);
    //     switch (value.module(f64)) {
    //         .@"n-ary" => |n_ary| {
    //             const bindings = n_ary.matches(parsed, gpa);

    //             if (bindings) |b| {
    //                 const solution = try n_ary.solve(parsed, b, .default, gpa);
    //                 std.mem.doNotOptimizeAway(solution.steps);
    //                 solution.deinit(gpa);
    //                 gpa.free(b);
    //             } else |_| {}
    //         },
    //         .dynamic => |dynamic| {
    //             const bindings = dynamic.matches(parsed);

    //             if (bindings) |b| {
    //                 const solution = try dynamic.solve(parsed, b, .default, gpa);
    //                 std.mem.doNotOptimizeAway(solution.steps);
    //                 solution.deinit(gpa);
    //             } else |_| {}
    //         },
    //         .structure => |structure| if (structural == comptime structure.ast.structural()) {
    //             if (structure.matches(parsed)) |bindings| {
    //                 const solution = try structure.solve(parsed, bindings, .default, allocator);
    //                 std.mem.doNotOptimizeAway(solution);
    //                 defer solution.deinit(allocator);
    //             } else |_| {}
    //         },
    //         .identity => |identity| if (hash == comptime identity.ast.hash()) {
    //             const solution = identity.proof(.default);
    //             std.mem.doNotOptimizeAway(solution);
    //         },
    //     }
    // }
}
