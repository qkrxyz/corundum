pub fn factorial(
    before: std.zig.Token.Tag,
    indices: *std.EnumMap(preprocess.Expression, usize),
    buffer: []u8,
    idx: *usize,
) !void {
    const idx_val = idx.*;

    const start_idx, const key = switch (before) {
        // implicit multiplication/function/parenthesis
        .r_paren => if (indices.get(.function)) |f| .{
            f,
            preprocess.Expression.function,
        } else if (indices.get(.number)) |n| .{
            n,
            preprocess.Expression.number,
        } else .{
            indices.get(.parenthesis) orelse return error.InvalidToken,
            preprocess.Expression.parenthesis,
        },

        .number_literal => .{ indices.getAssertContains(.number), preprocess.Expression.number },
        .identifier => .{ indices.getAssertContains(.identifier), preprocess.Expression.identifier },

        else => return error.InvalidToken,
    };

    const factorial_string = "factorial(";

    @memmove(buffer[factorial_string.len + start_idx .. factorial_string.len + idx_val], buffer[start_idx..idx_val]);
    @memcpy(buffer[start_idx .. start_idx + factorial_string.len], factorial_string);
    idx.* += factorial_string.len;

    buffer[idx.*] = ')';
    idx.* += 1;

    indices.remove(key);
}

pub fn indexOf(comptime T: type, input: []const T, scalar: T) ?usize {
    var remaining = input;
    var i: usize = 0;

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
