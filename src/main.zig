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

        try @import("main/preprocess.zig").preprocess(arguments[2], allocator, perf.rdtsc, perf.frequency, perf.ITERATIONS * 100);
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
