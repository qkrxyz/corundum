pub fn factorial(
    start_idx: usize,
    buffer: []u8,
    idx: *usize,
) !void {
    const idx_val = idx.*;

    const factorial_string = "factorial(";

    @memmove(buffer[factorial_string.len + start_idx .. factorial_string.len + idx_val], buffer[start_idx..idx_val]);
    @memcpy(buffer[start_idx .. start_idx + factorial_string.len], factorial_string);
    idx.* += factorial_string.len;

    buffer[idx.*] = ')';
    idx.* += 1;
}

pub fn indexOf(comptime T: type, input: []const T, scalar: T) ?u32 {
    var remaining = input;
    var i: u32 = 0;

    if (std.simd.suggestVectorLength(T)) |length| {
        const Chunk = @Vector(length, T);

        while (remaining.len >= length) {
            const slice = remaining[0..length];

            const chunk: Chunk = slice.*;
            const splatted: Chunk = @splat(scalar);

            const result = chunk == splatted;

            if (std.simd.firstTrue(result)) |j| return i + j;

            remaining = remaining[length..];
            i += length;
        }
    }

    for (remaining) |codepoint| {
        if (codepoint == scalar) return i;

        i += 1;
    }

    return null;
}

const std = @import("std");
const preprocess = @import("parser/preprocess");
