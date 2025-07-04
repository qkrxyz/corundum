const PREFIX = "const _ = ";
const POSTFIX = ";";

// https://ziglang.org/documentation/master/#Source-Encoding
const INVALID_BYTES: []const u8 = &[_]u8{
    0x0,  0x1,  0x2,  0x3,  0x4,  0x5,  0x6,  0x7,  0x8,  0xB,  0xC,  0xE,  0xF,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C,
    0x1D, 0x1E, 0x1F, 0x7F, 0x85,
};

const REPLACEMENTS: []const u8 = l18n.asBytes(l18n.RewriteInPlace.codepoints);

const MAX_DEPTH = 64;

// MARK: count
fn count(input: []const u8) !usize {
    var result: usize = input.len;

    // inspired by https://ziglang.org/documentation/master/std/#std.unicode.utf8ValidateSliceImpl
    var remaining = input;

    if (std.simd.suggestVectorLength(u8)) |length| {
        const Chunk = @Vector(length, u8);

        const equal: Chunk = @splat('=');
        const bang: Chunk = @splat('!');
        const apostrophe: Chunk = @splat('\'');
        const r_paren: Chunk = @splat(')');
        const l_paren: Chunk = @splat('(');
        const degree: Chunk = @splat('°');

        const multibyte_start: Chunk = @splat(0xC2); // 2 bytes long
        const multibyte_end: Chunk = @splat(0xF4); // 4 bytes long

        const digit_start: Chunk = @splat('0');
        const digit_end: Chunk = @splat('9');

        while (remaining.len >= length) {
            const slice = remaining[0..length];
            if (std.mem.indexOfAny(u8, slice, INVALID_BYTES) != null) return error.InvalidCharacter;

            const chunk: Chunk = slice.*;

            result += std.simd.countTrues(chunk == equal) * 2; // "==".len = 2
            result += std.simd.countTrues(chunk == bang) * 10; // "factorial(".len = 10
            result += std.simd.countTrues(chunk == apostrophe) * 11; // "derivative(".len = 11
            result += std.simd.countTrues(chunk == r_paren) * 2; // implicit multiplication
            result += std.simd.countTrues(chunk == l_paren) * 2; // implicit multiplication
            result += std.simd.countTrues(chunk == degree) * 7; // "degree(".len = 7

            const multibyte_start_mask = chunk >= multibyte_start;
            const multibyte_end_mask = chunk <= multibyte_end;
            const unicode = std.simd.countTrues(multibyte_start_mask & multibyte_end_mask) * 3;
            result += unicode; // the syntax for non-ASCII identifiers in Zig is `@"..."`, which adds 3 characters.

            const digit_start_mask = chunk >= digit_start;
            const digit_end_mask = chunk <= digit_end;
            result += std.simd.countTrues(digit_start_mask & digit_end_mask) * 2; // numbers can also implicitly multiply

            if (unicode != 0) {
                var i: usize = 0;
                while (i < slice.len) {
                    const codepoint = switch (slice[i]) {
                        // 2 bytes
                        0xC2...0xDF => blk: {
                            defer i += 1;
                            break :blk std.unicode.utf8Decode2(slice[i .. i + 2][0..2].*) catch return error.InvalidCharacter;
                        },

                        // 3 bytes
                        0xE0...0xEF => blk: {
                            defer i += 2;
                            break :blk std.unicode.utf8Decode3(slice[i .. i + 3][0..3].*) catch return error.InvalidCharacter;
                        },

                        // 4 bytes
                        0xF0...0xF4 => blk: {
                            defer i += 3;
                            break :blk std.unicode.utf8Decode4(slice[i .. i + 4][0..4].*) catch return error.InvalidCharacter;
                        },

                        // 1 byte
                        else => slice[i],
                    };

                    const data = l18n.RewriteInPlace.codepoints;

                    if (passes.indexOf(u21, &data, codepoint)) |idx| {
                        result += l18n.RewriteInPlace.inner[idx].rewrite.len + 3;
                        i += 1;
                    }

                    i += 1;
                }
            }

            remaining = remaining[length..];
        }
    }

    var i: usize = 0;
    while (i < remaining.len) {
        const char = remaining[i];
        if (passes.indexOf(u8, INVALID_BYTES, char) != null) return error.InvalidCharacter;

        switch (char) {
            // "==".len = 2
            '=' => result += 2,

            // "factorial(".len = 10
            '!' => result += 10,

            // "derivative(".len = 11
            '\'' => result += 11,

            // "degree(".len = 7
            '°' => result += 7,

            // implicit multiplication
            '(', ')', '0'...'9' => result += 1,

            else => {
                const codepoint = switch (char) {
                    // 2 bytes
                    0xC2...0xDF => blk: {
                        defer i += 1;
                        result += 1;
                        break :blk std.unicode.utf8Decode2(remaining[i .. i + 2][0..2].*) catch return error.InvalidCharacter;
                    },

                    // 3 bytes
                    0xE0...0xEF => blk: {
                        defer i += 2;
                        result += 2;
                        break :blk std.unicode.utf8Decode3(remaining[i .. i + 3][0..3].*) catch return error.InvalidCharacter;
                    },

                    // 4 bytes
                    0xF0...0xF4 => blk: {
                        defer i += 3;
                        result += 3;
                        break :blk std.unicode.utf8Decode4(remaining[i .. i + 4][0..4].*) catch return error.InvalidCharacter;
                    },

                    // 1 byte
                    else => char,
                };

                const data = l18n.RewriteInPlace.codepoints;

                if (passes.indexOf(u21, &data, codepoint)) |idx| {
                    result += l18n.RewriteInPlace.inner[idx].rewrite.len + 3;
                    // i += 1;
                }

                i += 1;
            },
        }

        i += 1;
    }

    return result;
}

pub const Token = struct {
    kind: enum {
        identifier,
        function,
        number,
        parenthesis,
    },

    depth: usize,
    index: usize,
};

pub const PreprocessingError = error{
    OutOfMemory,
    InvalidToken,
    InvalidCharacter,
};

// .identifier, .invalid -> `@"..."`
// .equal -> `==`
// .number_literal, .bang/.bang_equal -> `factorial(...)`[==]
// .number_literal/.r_paren, .l_paren -> `... * ...`
// MARK: preprocess
pub fn preprocess(comptime T: type, parser: *Parser(T)) PreprocessingError![:0]u8 {
    const length = try count(parser.input);
    var buffer: []u8 = try parser.allocator.alloc(u8, length + PREFIX.len + POSTFIX.len + 1);

    // modified when appending to the buffer
    var idx: usize = 0;

    // modified when resetting the tokenizer
    var offset: usize = 0;

    @memcpy(buffer[idx .. idx + PREFIX.len], PREFIX);
    idx += PREFIX.len;

    var tokenizer = std.zig.Tokenizer.init(parser.input);

    var depth: usize = 0;
    var token = tokenizer.next();
    var before: ?std.zig.Token.Tag = null;

    var indices: [MAX_DEPTH]usize = undefined;

    outer: while (token.tag != .eof) {
        switch (token.tag) {
            // MARK: invalid chars
            .invalid => {
                var end_idx: usize = 0;

                while (end_idx < parser.input.len) {
                    const codepoint_len: u3 = std.unicode.utf8ByteSequenceLength(parser.input[offset + token.loc.start + end_idx]) catch unreachable;
                    const input = parser.input[offset + token.loc.start + end_idx .. offset + token.loc.start + end_idx + codepoint_len];

                    const codepoint: u21 = switch (codepoint_len) {
                        1 => input[0],
                        2 => std.unicode.utf8Decode2(input[0..2].*),
                        3 => std.unicode.utf8Decode3(input[0..3].*),
                        4 => std.unicode.utf8Decode4(input[0..4].*),
                        else => unreachable,
                    } catch unreachable;

                    if (passes.indexOf(u21, l18n.Disallowed, codepoint) != null) return error.InvalidCharacter;
                    if (passes.indexOf(u21, l18n.Math.codepoint ++ l18n.Separator ++ l18n.Whitespace, codepoint) != null) break;

                    if (passes.indexOf(u21, &l18n.RewriteInPlace.codepoints, codepoint)) |index| {
                        if (before == .identifier) {
                            buffer[idx] = '\"';
                            idx += 1;
                        }

                        const rewrite = l18n.RewriteInPlace.inner[index].rewrite;

                        @memcpy(buffer[idx .. idx + rewrite.len], rewrite);
                        idx += rewrite.len;

                        // reset
                        if (offset + token.loc.start + end_idx >= parser.input.len) break :outer;

                        tokenizer = std.zig.Tokenizer.init(parser.input[offset + token.loc.start + end_idx + rewrite.len + 1 ..]);
                        offset += token.loc.start + end_idx + rewrite.len + 1;

                        before = .identifier;
                        token = tokenizer.next();
                        continue :outer;
                    }

                    end_idx += codepoint_len;
                }

                if (before != .identifier) {
                    @memcpy(buffer[idx .. idx + 2], "@\"");
                    idx += 2;

                    indices[depth] = idx - 2;
                }

                @memcpy(buffer[idx .. idx + end_idx], parser.input[offset + token.loc.start .. offset + token.loc.start + end_idx]);
                idx += end_idx;

                buffer[idx] = '\"';
                idx += 1;

                // reset
                if (offset + token.loc.start + end_idx >= parser.input.len) break;

                tokenizer = std.zig.Tokenizer.init(parser.input[offset + token.loc.start + end_idx ..]);
                offset += token.loc.start + end_idx;

                before = .identifier;
                token = tokenizer.next();
                continue;
            },

            // MARK: numbers
            .number_literal => {
                indices[depth] = idx;
                const token_length = token.loc.end - token.loc.start;

                @memcpy(buffer[idx .. idx + token_length], parser.input[offset + token.loc.start .. offset + token.loc.end]);
                idx += token_length;
            },

            // MARK: factorial
            .bang => {
                const start = indices[depth];
                try passes.factorial(start, buffer, &idx);
            },

            // MARK: identifier
            .identifier => {
                indices[depth] = idx;

                const token_length = token.loc.end - token.loc.start;
                before = token.tag;

                var next = tokenizer.next();
                switch (next.tag) {
                    // If invalid, this means that our identifier either contains an Unicode codepoint, or is before an Unicode character that should be replaced.
                    // Despite only the first case requiring this, it's generally safer to wrap the identifier in `@"..."`.
                    // MARK: complex identifier/derivative
                    .invalid => {
                        @memcpy(buffer[idx .. idx + 2], "@\"");
                        idx += 2;
                    },

                    // `<identifier>(` is a function call, and needs to be tracked.
                    // MARK: function call
                    .l_paren => {
                        indices[depth] = idx;

                        @memcpy(buffer[idx .. idx + token_length], parser.input[offset + token.loc.start .. offset + token.loc.end]);
                        idx += token_length;

                        buffer[idx] = '(';
                        idx += 1;
                        depth += 1;

                        before = next.tag;
                        next = tokenizer.next();
                        token = next;
                        continue;
                    },

                    else => {},
                }

                @memcpy(buffer[idx .. idx + token_length], parser.input[offset + token.loc.start .. offset + token.loc.end]);
                idx += token_length;

                token = next;
                continue;
            },

            // MARK: implicit multiplication
            // `...(` -> `... * (`, if the previous token is a number or a right parenthesis
            .l_paren => {
                if (before) |b| switch (b) {
                    .number_literal, .r_paren => {
                        buffer[idx] = '*';
                        idx += 1;
                    },

                    else => {},
                };

                indices[depth] = idx;

                buffer[idx] = '(';
                idx += 1;
                depth += 1;
            },

            // MARK: right parenthesis
            .r_paren => {
                buffer[idx] = ')';
                idx += 1;
                depth -= 1;
            },

            // MARK: double equals
            // `=` -> `==`
            .equal => {
                @memcpy(buffer[idx .. idx + 2], "==");
                idx += 2;
            },

            // "default" branch
            .plus, .minus, .asterisk, .slash => {
                const token_length = token.loc.end - token.loc.start;

                @memcpy(buffer[idx .. idx + token_length], parser.input[offset + token.loc.start .. offset + token.loc.end]);
                idx += token_length;
            },

            .eof => {},

            // MARK: derivation
            // Can be something like this: "f(x)' + g(x)'" or a double derivation ("f(x)''").
            // If this was a single derivation at the end, it would be an `.invalid`.
            .char_literal => {
                const token_length = token.loc.end - token.loc.start;

                // "''".len == 2; double derivation
                if (token_length == 2) {}
            },

            else => @panic(@tagName(token.tag)), //return error.InvalidToken,
        }

        before = token.tag;
        token = tokenizer.next();
    }

    @memcpy(buffer[idx .. idx + POSTFIX.len], POSTFIX);
    idx += POSTFIX.len;

    buffer[idx] = 0;

    return buffer[0..idx :0];
}

const std = @import("std");
const l18n = @import("parser/l18n");
const passes = @import("parser/passes");

const Parser = @import("parser").Parser;
