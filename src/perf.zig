const builtin = @import("builtin");
const std = @import("std");
const corundum = @import("corundum");

const expr = corundum.expr;
const template = corundum.template;

const ITERATIONS = (if (builtin.mode == .Debug) 5000 else 50000);
const total_runs = blk: {
    @setEvalBranchQuota((1 << 32) - 1);
    var result: usize = 0;
    for (std.meta.fieldNames(template.TemplatesKind)) |value| {
        if (std.mem.indexOf(u8, value, "metadata") != null) continue;

        result += template.Templates.tests(std.meta.stringToEnum(template.TemplatesKind, value).?, f64).kvs.len;
    }
    break :blk result;
};

pub fn Data(comptime T: type) type {
    return struct {
        kind: usize,
        name: []const u8,
        input: *const expr.Expression(T),
        outliers: usize,
        average: f64,
        mean: f64,
        std_dev: f64,
    };
}

pub fn PerfData(comptime T: type) type {
    return struct {
        zig_version: []u8,
        timestamp: i64,
        results: []Data(T),
        uncompressed: usize,
        compressed: usize,
    };
}

fn run(
    comptime T: type,
    comptime kind: template.TemplatesKind,
    input: *const expr.Expression(T),
    name: []const u8,
    progress: *std.Progress.Node,
    allocator: std.mem.Allocator,
) !Data(T) {
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

    // sort
    std.mem.sort(u64, &times, {}, std.sort.asc(u64));

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

        break :blk times[lower_idx..higher_idx];
    };

    var sum: u64 = 0;
    for (filtered) |value| {
        sum += value;
    }

    const average = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(filtered.len));

    // mean
    const mean: f64 = @floatFromInt(times[filtered.len / 2]);

    // std deviation
    var variance_sum: f64 = 0.0;
    for (filtered) |time| {
        const diff = @as(f64, @floatFromInt(time)) - average;
        variance_sum += diff * diff;
    }
    const variance = variance_sum / @as(f64, @floatFromInt(filtered.len));
    const std_deviation = @sqrt(variance);

    return Data(T){
        .kind = @intFromEnum(kind),
        .name = name,
        .input = input,
        .outliers = ITERATIONS - filtered.len,
        .average = average,
        .mean = mean,
        .std_dev = std_deviation,
    };
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

    var data: [total_runs]Data(f64) = undefined;
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
    progress.end();

    // file size
    const file = try std.fs.cwd().openFile("zig-out/wasm/corundum.wasm", .{});

    const contents = try file.readToEndAlloc(gpa, (1 << 32) - 1);
    var reader = std.io.fixedBufferStream(contents);
    defer gpa.free(contents);

    var output = std.ArrayList(u8).init(gpa);
    defer output.deinit();

    try std.compress.gzip.compress(reader.reader(), output.writer(), .{ .level = .best });

    // serialize
    const to_serialize = PerfData(f64){
        .zig_version = @constCast(builtin.zig_version_string),
        .timestamp = std.time.timestamp(),
        .results = &data,
        .uncompressed = contents.len,
        .compressed = output.items.len,
    };

    const output_file = try std.fs.cwd().createFile(try std.fmt.allocPrint(gpa, "assets/perf/{d}-{s}.zon", .{ to_serialize.timestamp, @tagName(builtin.mode) }), .{});
    try std.zon.stringify.serializeArbitraryDepth(to_serialize, .{ .emit_strings_as_containers = true, .whitespace = false }, output_file.writer());

    // compare
    var iterator = (try std.fs.cwd().openDir("./assets/perf", .{ .iterate = true })).iterate();
    var files = std.ArrayList(i64).init(gpa);

    while (try iterator.next()) |entry| {
        const dash_idx = std.mem.indexOfScalar(u8, entry.name, '-').?;
        const release_mode = std.meta.stringToEnum(std.builtin.OptimizeMode, entry.name[dash_idx + 1 .. entry.name.len - 4]).?;
        const timestamp = try std.fmt.parseInt(i64, entry.name[0..dash_idx], 10);

        if (release_mode == builtin.mode and timestamp != to_serialize.timestamp) {
            try files.append(timestamp);
        }
    }

    const slice = try files.toOwnedSlice();
    std.mem.sort(i64, slice, {}, std.sort.desc(i64));

    const last: ?PerfData(f64) = blk: {
        for (slice) |timestamp| {
            const opened = try std.fs.cwd().openFile(
                try std.fmt.allocPrint(gpa, "assets/perf/{d}-{s}.zon", .{ timestamp, @tagName(builtin.mode) }),
                .{},
            );
            const opened_contents = try opened.readToEndAlloc(gpa, (1 << 32) - 1);

            const value = try std.zon.parse.fromSlice(
                PerfData(f64),
                gpa,
                opened_contents[0..opened_contents.len :0],
                null,
                .{ .ignore_unknown_fields = true },
            );

            break :blk value;
        }

        break :blk null;
    };

    if (last) |before| {
        std.debug.print("\x1b[1mZig version\x1b[0m {s}, {s}\n", .{ before.zig_version, to_serialize.zig_version });
        std.debug.print("\x1b[1mTimestamp\x1b[0m {d}, {d}\n", .{ before.timestamp, to_serialize.timestamp });
        std.debug.print("\x1b[1mIterations\x1b[0m {d}\n", .{ITERATIONS});

        for (before.results) |value| {
            const after = blk: {
                for (to_serialize.results) |run_data| {
                    if (std.mem.eql(u8, run_data.name, value.name) and run_data.input.hash() == value.input.hash()) break :blk run_data;
                }

                @panic("every template from the last run must have a corresponding run from the current perf test");
            };

            const diff_avg = after.average - value.average;
            const percentage = (diff_avg / value.average) * 100;
            std.debug.print("\x1b[1m{s}\x1b[0m [{s}] // {d:.2} μs, {d:.2} μs // \x1b[4m{d: <4.2}%\x1b[0m ({d} outliers){s}\n", .{
                @tagName(@as(template.TemplatesKind, @enumFromInt(value.kind))),
                value.name,
                value.average / 1000,
                after.average / 1000,
                percentage,
                value.outliers,
                if (diff_avg > 1000 and percentage > 10.0) " \x1b[1;31mregressed\x1b[0m" else "",
            });
        }

        const diff_size = @as(isize, @intCast(to_serialize.compressed)) - @as(isize, @intCast(before.compressed));
        const percentage_size = @as(f64, @floatFromInt(diff_size)) / @as(f64, @floatFromInt(before.compressed)) * 100.0;
        std.debug.print(
            "\x1b[1mSize\x1b[0m {d:.2}/{d:.2} KB, {d:.2}/{d:.2} KB // \x1b[4m{d:.2}%\x1b[0m{s}\n",
            .{
                before.uncompressed,
                before.compressed,
                to_serialize.uncompressed,
                to_serialize.compressed,
                percentage_size,
                if (percentage_size > 5.0) " \x1b[1;31mregressed\x1b[0m" else "",
            },
        );
    } else {
        std.debug.print("\x1b[1mZig version\x1b[0m {s}\n", .{to_serialize.zig_version});
        std.debug.print("\x1b[1mTimestamp\x1b[0m {d}\n", .{to_serialize.timestamp});
        std.debug.print("\x1b[1mIterations\x1b[0m {d}\n", .{ITERATIONS});
        for (to_serialize.results) |run_data| {
            std.debug.print("\x1b[1m{s}\x1b[0m [{s}] // {d:.2} μs ({d} outliers)\n", .{
                @tagName(@as(template.TemplatesKind, @enumFromInt(run_data.kind))),
                run_data.name,
                run_data.average / 1000,
                run_data.outliers,
            });
        }
        std.debug.print("\x1b[1mSize\x1b[0m {d:.2}/{d:.2} KB\n", .{ to_serialize.uncompressed, to_serialize.compressed });
    }
}
