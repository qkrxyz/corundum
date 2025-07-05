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

    const arguments = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, arguments);

    if (arguments.len < 2) return;

    // actual work
    var handles: [3]std.Thread = undefined;

    var parent = std.Progress.start(.{ .root_name = "Benchmarking...", .estimated_total_items = handles.len });
    defer parent.end();

    const perf = @import("perf.zig");

    handles[0] = try std.Thread.spawn(
        .{},
        @import("main/preprocess.zig").preprocess,
        .{ arguments[1], gpa, &parent, perf.rdtsc, perf.frequency, perf.ITERATIONS * 100 },
    );

    handles[1] = try std.Thread.spawn(
        .{},
        @import("main/parse.zig").parse,
        .{ f64, arguments[1], gpa, &parent, perf.rdtsc, perf.frequency, perf.ITERATIONS * 100 },
    );

    handles[2] = try std.Thread.spawn(
        .{},
        @import("main/engine.zig").engine,
        .{ f64, arguments[1], gpa, &parent, perf.rdtsc, perf.frequency, perf.ITERATIONS * 100 },
    );

    for (handles) |handle| handle.join();
}
