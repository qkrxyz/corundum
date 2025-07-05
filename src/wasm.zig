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

    var output = std.ArrayList(u8).init(allocator);

    const engine = corundum.engine.Engine(T).init(allocator, slice);
    const solution = engine.run() catch |err| {
        switch (err) {
            error.OutOfMemory => @panic("out of memory"),
            error.InvalidCharacter, error.InvalidToken => output.appendSlice("invalid syntax") catch unreachable,
            error.NoTemplateFound => output.appendSlice("no template found") catch unreachable,
        }

        const result_slice = output.toOwnedSlice() catch @panic("out of memory");

        const new_ptr_addr: u64 = @intFromPtr(result_slice.ptr);
        const result = (new_ptr_addr << 32) | result_slice.len;

        return result;
    };
    defer solution.deinit(allocator);

    std.zon.stringify.serializeArbitraryDepth(solution, .{}, output.writer()) catch unreachable;

    const result_slice = output.toOwnedSlice() catch @panic("out of memory");

    const new_ptr_addr: u64 = @intFromPtr(result_slice.ptr);
    const result = (new_ptr_addr << 32) | result_slice.len;

    return result;
}
