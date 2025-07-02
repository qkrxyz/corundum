const ExprType = enum {
    parens,
    identifier,
    function,
};

pub fn preprocess(comptime T: type, self: *Parser(T), comptime pre: []const u8, comptime post: []const u8) !void {
    // the maximum additional count of characters these characters require.
    // equals, degree, factorial, unicode characters, implicit multiplication.
    const costs: @Vector(5, usize) = .{ 1, 7, 10, 3, 1 };

    // equals, degree, factorial, unicode characters, implicit multiplication.
    var counts: @Vector(5, usize) = .{ 0, 0, 0, 0, 0 };

    var i: usize = 0;
    var ch = self.input[i];

    while (i < self.input.len) {
        switch (ch) {
            // disallowed characters - https://ziglang.org/documentation/master/#Source-Encoding
            0x0...0x8, 0xB...0xC, 0xE...0x1F, 0x7F, 0x85 => {
                @branchHint(.cold);

                return error.InvalidCharacter;
            },

            '=' => counts[0] += 1,

            '°' => {
                @branchHint(.unlikely);

                counts[1] += 1;
            },

            '!' => counts[2] += 1,

            // standard ASCII characters
            0x9...0xA,
            0xD,
            0x20,
            0x22...0x28,
            0x2A...0x2F,
            0x3A...0x3C,
            0x3E...0x40,
            0x5B...0x60,
            0x7B...0x7E,
            0x80...0x84,
            0x86...0xAF,
            0xB1...0xBF,
            0xF8...0xFF,
            => {},

            // )
            0x29 => counts[4] += 1,

            // numbers - can have an implicit multiplication
            0x30...0x39 => {
                @branchHint(.likely);

                if (i + 1 < self.input.len) switch (self.input[i + 1]) {
                    0x41...0x5A, // A-Z
                    0x61...0x7A, // a-z
                    0x28,
                    0x29, // (, )
                    => {
                        counts[4] += 1;
                    },

                    // UTF-8 start bytes
                    0xC0...0xF7,
                    => {
                        counts[3] += 1;
                        counts[4] += 1;

                        i += try std.unicode.utf8ByteSequenceLength(ch) - 1;
                    },

                    else => {},
                };
            },

            // letters - also can have an implicit multiplication
            0x41...0x5A,
            0x61...0x7A,
            => {
                @branchHint(.likely);

                if (i + 1 < self.input.len) switch (self.input[i + 1]) {
                    // (, )
                    0x28, 0x29 => counts[4] += 1,

                    else => {},
                };
            },

            // UTF-8 start bytes, need to be encoded using `@"..."`. And just in case also increment the implicit multiplication counter.
            0xC0...0xF7,
            => {
                counts[3] += 1;
                counts[4] += 1;

                i += try std.unicode.utf8ByteSequenceLength(ch) - 1;
            },
        }

        i += 1;
        ch = self.input[i];
    }

    try self.buffer.ensureTotalCapacityPrecise(self.input.len + @reduce(.Add, costs * counts) + pre.len + post.len);
    self.buffer.appendSliceAssumeCapacity(pre);

    var before: ?std.zig.Token.Tag = null;

    var indices: std.EnumMap(ExprType, usize) = .init(.{});

    var tokenizer = std.zig.Tokenizer.init(self.input);

    var token = tokenizer.next();
    var offset: usize = 0;

    state: switch (token.tag) {
        .invalid => {
            const slice = self.input[offset + token.loc.start .. offset + token.loc.end];

            if (!std.unicode.utf8ValidateSlice(slice)) return error.InvalidCharacter;

            var end_idx: usize = 0;

            while (end_idx < slice.len) {
                const len = try std.unicode.utf8ByteSequenceLength(slice[end_idx]);
                const codepoint: u21 = switch (len) {
                    1 => slice[end_idx],
                    2 => std.unicode.utf8Decode2(slice[end_idx .. end_idx + 2][0..2].*),
                    3 => std.unicode.utf8Decode3(slice[end_idx .. end_idx + 3][0..3].*),
                    4 => std.unicode.utf8Decode4(slice[end_idx .. end_idx + 4][0..4].*),
                    else => unreachable,
                } catch return error.InvalidCharacter;

                // TODO simd? @reduce(.Or, @splat(codepoint) == l18n.<...>) == true
                if (std.mem.indexOfScalar(
                    u21,
                    l18n.Disallowed,
                    codepoint,
                ) != null) {
                    @branchHint(.cold);

                    return error.InvalidCharacter;
                }

                if (std.mem.indexOfScalar(
                    u21,
                    l18n.Whitespace ++ l18n.Separator ++ l18n.Math.codepoint,
                    codepoint,
                ) != null) {
                    break;
                }

                end_idx += len;
            }

            if (before != .identifier) self.buffer.appendSliceAssumeCapacity("@\"");
            self.buffer.appendSliceAssumeCapacity(slice[0..end_idx]);
            self.buffer.appendAssumeCapacity('\"');

            // reset
            if (offset + token.loc.start + end_idx >= self.input.len) continue :state .eof;

            tokenizer = std.zig.Tokenizer.init(self.input[offset + token.loc.start + end_idx .. self.input.len :0]);

            offset += token.loc.start + end_idx;
            before = .identifier;

            token = tokenizer.next();
            continue :state token.tag;
        },

        .identifier => {
            @branchHint(.likely);

            indices.put(.identifier, self.buffer.items.len);
            before = .identifier;

            const next = tokenizer.next();
            switch (next.tag) {
                .invalid => self.buffer.appendSliceAssumeCapacity("@\""),

                else => {},
            }

            self.buffer.appendSliceAssumeCapacity(self.input[offset + token.loc.start .. offset + token.loc.end]);

            token = next;
            continue :state token.tag;
        },

        .eof => {},

        // `!`, ...
        .bang => {
            var next = tokenizer.next();
            if (next.tag == .equal) {
                self.buffer.appendSliceAssumeCapacity("!=");

                next = tokenizer.next();
            } else {
                self.buffer.appendAssumeCapacity('!');
            }

            token = next;
            continue :state token.tag;
        },

        .equal => {
            self.buffer.appendSliceAssumeCapacity("==");
            before = .equal;

            token = tokenizer.next();
            continue :state token.tag;
        },

        // can have implicit multiplication
        .l_paren => {
            indices.put(.parens, self.buffer.items.len + 1);

            if (before) |before_tag| switch (before_tag) {
                .number_literal,
                .r_paren,
                => {
                    self.buffer.appendSliceAssumeCapacity("*(");
                    indices.getPtrAssertContains(.parens).* += 1;

                    before = .l_paren;
                    token = tokenizer.next();
                    continue :state token.tag;
                },

                // function call
                .identifier => {
                    indices.put(.function, indices.getAssertContains(.identifier));
                },

                else => {},
            };

            self.buffer.appendAssumeCapacity('(');

            before = .l_paren;
            token = tokenizer.next();

            continue :state token.tag;
        },

        .r_paren => {
            var next = tokenizer.next();

            switch (next.tag) {
                // ...!=... (!, =) -  ...)!, <number>! and <identifier>! are factorials
                .bang, .bang_equal => {
                    const factorial = "factorial";

                    const parens_idx = indices.get(.parens) orelse return error.ParenthesisNotOpened;

                    var previous_len = self.buffer.items.len;
                    self.buffer.items.len += factorial.len;

                    // parens_idx is the index of the first character _inside_ the parenthesis opened most recently.
                    @memmove(self.buffer.items[parens_idx + factorial.len - 1 ..], self.buffer.items[parens_idx - 1 .. previous_len]);
                    @memcpy(self.buffer.items[parens_idx - 1 .. parens_idx + factorial.len - 1], factorial);

                    previous_len = self.buffer.items.len;

                    if (next.tag == .bang_equal) {
                        self.buffer.items.len += 3;

                        @memcpy(self.buffer.items[previous_len..self.buffer.items.len], ")==");
                        before = .equal;
                    } else {
                        self.buffer.items.len += 1;

                        @memcpy(self.buffer.items[previous_len..self.buffer.items.len], ")");
                        before = .r_paren;
                    }

                    token = tokenizer.next();

                    continue :state token.tag;
                },

                .invalid => if (next.tag == .invalid and next.loc.end - next.loc.start == 1 and self.input[offset + next.loc.start] == '\'') {
                    // derivatives
                    const beginning = (indices.get(.function) orelse return error.InvalidDerivative);

                    const derivative = "derivative(";

                    const previous_len = self.buffer.items.len;

                    self.buffer.items.len += derivative.len;

                    @memmove(self.buffer.items[beginning + derivative.len ..], self.buffer.items[beginning..previous_len]);
                    @memcpy(self.buffer.items[beginning .. beginning + derivative.len], derivative);
                    self.buffer.appendAssumeCapacity(')');

                    next = tokenizer.next();
                },

                else => {},
            }

            self.buffer.appendAssumeCapacity(')');

            before = .r_paren;
            token = next;

            continue :state token.tag;
        },

        // TODO create a list of valid tags
        else => |tag| {
            const slice = self.input[offset + token.loc.start .. offset + token.loc.end];

            const next = tokenizer.next();

            switch (next.tag) {
                // ...(... - implicit multiplication; previous token must be a right parenthesis or number
                .l_paren => {
                    switch (tag) {
                        .number_literal,
                        .r_paren,
                        => {
                            self.buffer.appendSliceAssumeCapacity(slice);
                            self.buffer.appendSliceAssumeCapacity("*(");

                            before = .l_paren;
                            indices.put(.parens, self.buffer.items.len);

                            token = tokenizer.next();
                            continue :state token.tag;
                        },

                        else => {},
                    }
                },

                .bang, .bang_equal => switch (token.tag) {
                    .number_literal,
                    .identifier,
                    .string_literal,
                    => {
                        self.buffer.appendSliceAssumeCapacity("factorial(");
                        self.buffer.appendSliceAssumeCapacity(slice);
                        self.buffer.appendAssumeCapacity(')');
                        before = .r_paren;

                        if (next.tag == .bang_equal) {
                            self.buffer.appendSliceAssumeCapacity("==");
                            before = .equal;
                        }

                        token = tokenizer.next();

                        continue :state token.tag;
                    },

                    else => {
                        self.buffer.appendSliceAssumeCapacity(slice);

                        before = tag;
                        token = tokenizer.next();
                        continue :state token.tag;
                    },
                },

                .invalid => {
                    const new_slice = self.input[offset + next.loc.start .. offset + next.loc.end];

                    if (std.mem.eql(u8, new_slice[0..2], &.{ 0xC2, 0xB0 })) {
                        self.buffer.appendSliceAssumeCapacity("degree(");
                        self.buffer.appendSliceAssumeCapacity(slice);
                        self.buffer.appendAssumeCapacity(')');

                        // reset
                        if (offset + token.loc.start + 1 >= self.input.len) continue :state .eof;

                        tokenizer = std.zig.Tokenizer.init(self.input[offset + token.loc.start + 4 .. self.input.len :0]);
                        offset += token.loc.start + 4;

                        before = .r_paren;
                        token = tokenizer.next();

                        continue :state token.tag;
                    }
                },

                else => {},
            }

            self.buffer.appendSliceAssumeCapacity(slice);

            before = tag;
            token = next;

            continue :state token.tag;
        },
    }

    self.buffer.appendSliceAssumeCapacity(post);
}

test preprocess {
    const input = "3! + 30° = 🥰";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess2" {
    const input = "3!=6";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess3" {
    const input = "(n - 1)!=6";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess4" {
    const input = "2(n - 1)";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess5" {
    const input = "x(x + 1)";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    const err = p.preprocess();
    try testing.expectError(error.AmbiguousMultiplication, err);

    std.debug.print("before: `{s}`\nafter: `{any}`\n", .{ input, err });
}

test "preprocess6" {
    const input = "🐈(🐈 + 1)";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    const err = p.preprocess();
    try testing.expectError(error.AmbiguousMultiplication, err);

    std.debug.print("before: `{s}`\nafter: `{any}`\n", .{ input, err });
}

test "preprocess7" {
    const input = "(x - 1)(x + 1)";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess8" {
    const input = "ogórek = 3";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

const std = @import("std");
const parser = @import("parser");

const testing = std.testing;
const Parser = parser.Parser;
const l18n = @import("parser/l18n");
