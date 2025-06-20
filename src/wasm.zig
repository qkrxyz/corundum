const std = @import("std");

pub const expression = @import("expr");
pub const template = @import("template");
const T: type = f64;

var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
const allocator = arena.allocator();

pub export fn alloc(len: usize) [*]u8 {
    return (allocator.alloc(u8, len) catch @panic("Out of memory")).ptr;
}

pub export fn free(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

pub export fn solve(string: [*:0]u8, length: usize) ?*const []*const template.Step(T) {
    const slice = string[0..length :0];
    const parsed = std.zon.parse.fromSlice(expression.Expression(T), allocator, slice, null, .{});

    if (parsed) |expr| {
        const structural = expr.structural();
        const hash = expr.hash();

        inline for (template.Templates.all()) |kind| {
            const value = template.Templates.get(kind);
            switch (value.module(f64)) {
                .dynamic => |dynamic| {
                    const bindings = if (@typeInfo(@TypeOf(dynamic.matches)).@"fn".params.len == 2) dynamic.matches(&expr, allocator) else dynamic.matches(&expr);

                    if (bindings) |b| {
                        const solution = dynamic.solve(&expr, b, allocator) catch unreachable;

                        return &solution.steps;
                    } else |_| {}
                },
                .structure => |structure| {
                    if (structural == comptime structure.ast.structural()) {
                        const bindings = structure.matches(&expr) catch unreachable;
                        const solution = structure.solve(&expr, bindings, allocator) catch unreachable;

                        return &solution.steps;
                    }
                },
                .identity => |identity| {
                    if (hash == comptime identity.ast.hash()) {
                        const solution = identity.proof();

                        return &solution.steps;
                    }
                },
            }
        }
    } else |_| {
        @panic("error");
    }

    return null;
}
