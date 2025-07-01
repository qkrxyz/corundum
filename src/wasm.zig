const std = @import("std");
const corundum = @import("corundum");

const expression = corundum.expr;
const template = corundum.template;
const T = f64;

const allocator = std.heap.wasm_allocator;

export fn alloc(len: usize) usize {
    const ptr = allocator.alloc(u8, len) catch @panic("out of memory");
    return @intFromPtr(ptr.ptr);
}

export fn free(ptr: usize, len: usize) void {
    allocator.free(@as([*]u8, @ptrFromInt(ptr))[0..len]);
}

export fn solve(string: [*]u8, length: usize) u64 {
    const slice = string[0..length :0];
    const parsed = std.zon.parse.fromSlice(*const expression.Expression(T), allocator, slice, null, .{});

    var output = std.ArrayList(u8).init(allocator);

    if (parsed) |expr| {
        const structural = expr.structural();
        const hash = expr.hash();

        inline for (corundum.template.Templates.all()) |t| {
            const value = corundum.template.Templates.get(t);
            switch (value.module(f64)) {
                .@"n-ary" => |n_ary| {
                    const bindings = n_ary.matches(expr, allocator);

                    if (bindings) |b| {
                        const solution = n_ary.solve(expr, b, .default, allocator) catch @panic("out of memory");
                        defer solution.deinit(allocator);
                        defer allocator.free(b);

                        std.zon.stringify.serializeArbitraryDepth(solution, .{}, output.writer()) catch @panic("out of memory");
                        output.append('\n') catch @panic("out of memory");
                    } else |_| {}
                },
                .dynamic => |dynamic| {
                    const bindings = dynamic.matches(expr);

                    if (bindings) |b| {
                        output.writer().print("{s}: ", .{dynamic.name}) catch @panic("out of memory");
                        const solution = dynamic.solve(expr, b, .default, allocator) catch @panic("out of memory");
                        defer solution.deinit(allocator);

                        std.zon.stringify.serializeArbitraryDepth(solution, .{}, output.writer()) catch @panic("out of memory");
                        output.append('\n') catch @panic("out of memory");
                    } else |_| {
                        // output.writer().print("{}: {}\n", .{ t, err }) catch @panic("out of memory");
                    }
                },
                .structure => |structure| {
                    if (structural == comptime structure.ast.structural()) {
                        if (structure.matches(expr)) |bindings| {
                            output.writer().print("{s}: ", .{structure.name}) catch @panic("out of memory");

                            const solution = structure.solve(expr, bindings, .default, allocator) catch @panic("out of memory");
                            defer solution.deinit(allocator);

                            std.zon.stringify.serializeArbitraryDepth(solution, .{}, output.writer()) catch @panic("out of memory");
                            output.append('\n') catch @panic("out of memory");
                        } else |_| {}
                    } else {
                        // output.writer().print("{}: doesn't match\n", .{t}) catch @panic("out of memory");
                    }
                },
                .identity => |identity| {
                    if (hash == comptime identity.ast.hash()) {
                        output.writer().print("{s}: ", .{identity.name}) catch @panic("out of memory");

                        const solution = identity.proof(.default);
                        std.zon.stringify.serializeArbitraryDepth(solution, .{}, output.writer()) catch @panic("out of memory");
                        output.append('\n') catch @panic("out of memory");
                    } else {
                        // output.writer().print("{}: doesn't match\n", .{t}) catch @panic("out of memory");
                    }
                },
            }
        }
    } else |err| switch (err) {
        error.OutOfMemory => @panic("out of memory"),
        error.ParseZon => output.appendSlice("failed to parse ZON") catch @panic("out of memory"),
    }

    const result_slice = output.toOwnedSlice() catch @panic("out of memory");

    const new_ptr_addr: u64 = @intFromPtr(result_slice.ptr);
    const result = (new_ptr_addr << 32) | result_slice.len;

    return result;
}
