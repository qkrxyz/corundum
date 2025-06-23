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

    std.debug.print("templates (in order):\n", .{});
    inline for (corundum.template.Templates.all()) |template| {
        std.debug.print("{}\n", .{template});
    }

    if (arguments.len >= 2) {
        var diagnostics: std.zon.parse.Status = .{};

        const parsed = std.zon.parse.fromSlice(corundum.expression.Expression(f64), allocator, arguments[1], &diagnostics, .{}) catch {
            var error_iterator = diagnostics.iterateErrors();
            while (error_iterator.next()) |err| {
                const stderr = std.io.getStdErr().writer();
                try err.fmtMessage(&diagnostics).format("error: {s}\n", .{}, stderr);
            }

            std.process.exit(1);
        };

        try benchmark2(allocator, &parsed);
        std.debug.print("parsed: {any}\n\n", .{parsed});

        try run(benchmark2, .{ allocator, &parsed });
    }
}

fn run(function: anytype, arguments: anytype) !void {
    // benchmarks
    const ITERATIONS = 100000;
    var progress = std.Progress.start(.{ .estimated_total_items = ITERATIONS, .root_name = "Running benchmarks..." });

    var results: [ITERATIONS]u64 = undefined;
    for (0..ITERATIONS) |i| {
        var timer = try std.time.Timer.start();

        try @call(.always_inline, function, arguments);

        results[i] = timer.read();
        progress.completeOne();
    }

    progress.end();

    // average
    var sum: u64 = 0;
    for (results) |value| {
        sum += value;
    }

    const average = @as(f64, @floatFromInt(sum)) / ITERATIONS;

    // mean
    // std.mem.sort(u64, &results, {}, std.sort.asc(u64));
    // const mean = results[ITERATIONS / 2];

    // std deviation
    var variance_sum: f64 = 0.0;
    for (results) |time| {
        const diff = @as(f64, @floatFromInt(time)) - average;
        variance_sum += diff * diff;
    }
    const variance = variance_sum / ITERATIONS;
    const std_deviation = @sqrt(variance);

    std.debug.print("\x1b[1maverage ± σ\x1b[0m\n", .{});
    printTime(average);
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

fn benchmark2(allocator: std.mem.Allocator, expression: *const corundum.expression.Expression(f64)) !void {
    const structural = expression.structural();
    const hash = expression.hash();

    // const stderr = std.io.getStdErr().writer();

    inline for (corundum.template.Templates.all()) |template| {
        const value = corundum.template.Templates.get(template);
        switch (value.module(f64)) {
            .dynamic => |dynamic| {
                const bindings = if (@typeInfo(@TypeOf(dynamic.matches)).@"fn".params.len == 2) dynamic.matches(expression, allocator) else dynamic.matches(expression);

                if (bindings) |b| {
                    // std.debug.print("{}: ", .{template});
                    const solution = try dynamic.solve(expression, b, allocator);
                    std.mem.doNotOptimizeAway(solution);
                    defer solution.deinit(allocator);

                    // try std.zon.stringify.serializeArbitraryDepth(solution, .{}, stderr);
                    // std.debug.print("\n", .{});
                } else |_| {
                    // std.debug.print("{}: {}\n", .{ template, err });
                }
            },
            .structure => |structure| {
                if (structural == comptime structure.ast.structural()) {
                    // std.debug.print("{}: ", .{template});

                    if (structure.matches(expression)) |bindings| {
                        const solution = try structure.solve(expression, bindings, allocator);
                        std.mem.doNotOptimizeAway(solution);
                        defer solution.deinit(allocator);

                        // try std.zon.stringify.serializeArbitraryDepth(solution, .{}, stderr);
                        // std.debug.print("\n", .{});
                    } else |_| {}
                } else {
                    // std.debug.print("{}: doesn't match\n", .{template});
                }
            },
            .identity => |identity| {
                if (hash == comptime identity.ast.hash()) {
                    // std.debug.print("{}: {any}\n", .{ template, hash == comptime identity.ast.hash() });
                    // std.debug.print("{}: ", .{template});

                    const solution = identity.proof();
                    std.mem.doNotOptimizeAway(solution);
                    // try std.zon.stringify.serializeArbitraryDepth(solution, .{}, stderr);
                    // std.debug.print("\n", .{});
                } else {
                    // std.debug.print("{}: doesn't match\n", .{template});
                }
            },
        }
    }
}
