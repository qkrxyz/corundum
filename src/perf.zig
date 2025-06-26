const builtin = @import("builtin");
const std = @import("std");
const corundum = @import("corundum");

const expr = corundum.expr;
const template = corundum.template;

const ITERATIONS = (if (builtin.mode == .Debug) 10000 else 100000);
const total_runs = blk: {
    @setEvalBranchQuota((1 << 32) - 1);
    var result: usize = 0;
    for (std.meta.fieldNames(template.TemplatesKind)) |value| {
        if (std.mem.indexOf(u8, value, "metadata") != null) continue;

        result += template.Templates.tests(std.meta.stringToEnum(template.TemplatesKind, value).?, f64).kvs.len;
    }
    break :blk result;
};

const Data = struct {
    name: []const u8,
    average: f64,
    mean: f64,
    std_dev: f64,
};

fn run(
    comptime T: type,
    comptime kind: template.TemplatesKind,
    input: *const expr.Expression(T),
    name: []const u8,
    progress: *std.Progress.Node,
    allocator: std.mem.Allocator,
) !Data {
    const t = template.Templates.get(kind);

    const this = progress.start(if (@typeInfo(@TypeOf(t)) == .@"struct") switch (t.module(T)) {
        .dynamic => |dynamic| dynamic.name,
        .structure => |structure| structure.name,
        .identity => |identity| identity.name,
    } else t(T).name, ITERATIONS);

    var times: [ITERATIONS]u64 = undefined;

    for (0..ITERATIONS) |i| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const gpa = arena.allocator();

        var timer = try std.time.Timer.start();

        const structural = input.structural();
        const hash = input.hash();

        if (@typeInfo(@TypeOf(t)) == .@"struct") {
            switch (t.module(T)) {
                .dynamic => |dynamic| {
                    const bindings = if (@typeInfo(@TypeOf(dynamic.matches)).@"fn".params.len == 2) dynamic.matches(input, gpa) else dynamic.matches(input);

                    if (bindings) |b| {
                        const solution = try dynamic.solve(input, b, gpa);
                        std.mem.doNotOptimizeAway(solution.steps);
                        solution.deinit(gpa);

                        if (@typeInfo(@TypeOf(dynamic.matches)).@"fn".params.len == 2) gpa.free(b);
                    } else |_| {}
                },
                .structure => |structure| {
                    if (structural == comptime structure.ast.structural()) {
                        if (structure.matches(input)) |bindings| {
                            const solution = try structure.solve(input, bindings, gpa);
                            std.mem.doNotOptimizeAway(solution.steps);
                            solution.deinit(gpa);
                        } else |_| {}
                    }
                },
                .identity => |identity| {
                    if (hash == comptime identity.ast.hash()) {
                        const solution = identity.proof();
                        std.mem.doNotOptimizeAway(solution.steps);
                    }
                },
            }
        } else {
            if (t(T).matches(input)) |bindings| {
                const solution = try t(T).solve(input, bindings, gpa);
                std.mem.doNotOptimizeAway(solution.steps);
                solution.deinit(gpa);
            } else |_| {}
        }

        const took = timer.read();

        times[i] = took;
        this.completeOne();
    }

    this.end();

    var sum: u64 = 0;
    for (times) |value| {
        sum += value;
    }

    const average = @as(f64, @floatFromInt(sum)) / ITERATIONS;

    // mean
    std.mem.sort(u64, &times, {}, std.sort.asc(u64));
    const mean: f64 = @floatFromInt(times[ITERATIONS / 2]);

    // std deviation
    var variance_sum: f64 = 0.0;
    for (times) |time| {
        const diff = @as(f64, @floatFromInt(time)) - average;
        variance_sum += diff * diff;
    }
    const variance = variance_sum / ITERATIONS;
    const std_deviation = @sqrt(variance);

    return Data{ .average = average, .mean = mean, .std_dev = std_deviation, .name = try std.mem.join(allocator, "", &.{ "\x1b[1m" ++ @tagName(kind) ++ "\x1b[0m [", name, "]" }) };
}

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

    var data: [total_runs]Data = undefined;
    var idx: usize = 0;

    var progress = std.Progress.start(.{ .estimated_total_items = total_runs, .root_name = "Running benchmarks..." });

    inline for (std.meta.fields(template.TemplatesKind)) |entry| {
        @setEvalBranchQuota((1 << 32) - 1);
        if (comptime std.mem.indexOf(u8, entry.name, "metadata") == null) {
            const kind: template.TemplatesKind = @enumFromInt(entry.value);
            const testing_data = template.Templates.tests(kind, f64);

            for (testing_data.keys()) |key| {
                data[idx] = try run(
                    f64,
                    kind,
                    testing_data.get(key).?,
                    key,
                    &progress,
                    gpa,
                );

                idx += 1;
            }
        }
    }

    for (data) |entry| {
        std.debug.print("{s}: {d:.2} μs ± {d:.2} μs\n", .{ entry.name, entry.mean / 1000, entry.std_dev / 1000 });
    }

    progress.end();

    const file = try std.fs.cwd().openFile("zig-out/wasm/corundum.wasm", .{});

    const contents = try file.readToEndAlloc(gpa, (1 << 32) - 1);
    var reader = std.io.fixedBufferStream(contents);
    defer gpa.free(contents);

    std.debug.print("Uncompressed size: {d} bytes\n", .{contents.len});

    var output = std.ArrayList(u8).init(gpa);
    defer output.deinit();

    try std.compress.gzip.compress(reader.reader(), output.writer(), .{ .level = .best });

    std.debug.print("Compressed size: {d} bytes\n", .{output.items.len});
}
