pub fn preprocess(comptime T: type, self: *Parser(T)) !void {
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

    try self.buffer.ensureTotalCapacityPrecise(self.input.len + @reduce(.Add, costs * counts));

    var before: ?std.zig.Token.Tag = null;
    var parens_idx: ?usize = null;

    var tokenizer = std.zig.Tokenizer.init(self.input);

    var token = tokenizer.next();
    var offset: usize = 0;

    state: switch (token.tag) {
        .invalid => {
            // TODO handle cases when `°` is without a value
            const slice = self.input[offset + token.loc.start .. offset + token.loc.end];

            if (!std.unicode.utf8ValidateSlice(slice)) return error.InvalidCharacter;

            // we only need to check for 0x2028 and 0x2029, otherwise it's a valid character that can be used as a `@"..."`.
            const len = try std.unicode.utf8ByteSequenceLength(slice[0]);
            const codepoint = switch (len) {
                1 => @as(u21, slice[0]),
                2 => std.unicode.utf8Decode2(@constCast(slice[0..2]).*),
                3 => std.unicode.utf8Decode3(@constCast(slice[0..3]).*),
                4 => std.unicode.utf8Decode4(@constCast(slice[0..4]).*),
                else => unreachable,
            } catch return error.InvalidCharacter;

            switch (codepoint) {
                // https://ziglang.org/documentation/master/#Source-Encoding
                0x2028, 0x2029 => {
                    @branchHint(.cold);

                    return error.InvalidCharacter;
                },

                // https://en.wikipedia.org/wiki/Whitespace_character#Unicode; ignore whitespaces
                0xA0, 0x1680, 0x180E, 0x2000...0x200D, 0x202F, 0x205F...0x2060, 0x3000, 0xFEFF => {},

                else => {
                    self.buffer.appendSliceAssumeCapacity("@\"");
                    self.buffer.appendSliceAssumeCapacity(self.input[offset + token.loc.start .. offset + token.loc.start + len]);
                    self.buffer.appendAssumeCapacity('\"');

                    // reset
                    if (offset + token.loc.start + len >= self.input.len) continue :state .eof;

                    tokenizer = std.zig.Tokenizer.init(self.input[offset + token.loc.start + len .. self.input.len :0]);
                    offset += token.loc.start + len;

                    token = tokenizer.next();
                    before = .identifier;

                    continue :state token.tag;
                },
            }
        },

        .eof => {},

        // `!`, ...
        .bang => {
            const next = tokenizer.next();
            if (next.tag == .equal) {
                self.buffer.appendSliceAssumeCapacity("!=");
            }
        },

        .equal => {
            self.buffer.appendSliceAssumeCapacity("==");
            before = .equal;

            token = tokenizer.next();
            continue :state token.tag;
        },

        // can have implicit multiplication
        .l_paren => {
            parens_idx = self.buffer.items.len + 1;

            if (before) |before_tag| switch (before_tag) {
                .number_literal,
                .identifier,
                .r_paren,
                => {
                    self.buffer.appendSliceAssumeCapacity("*(");
                    parens_idx.? += 1;

                    before = .l_paren;
                    token = tokenizer.next();
                    continue :state token.tag;
                },

                else => {},
            };

            self.buffer.appendAssumeCapacity('(');

            before = .l_paren;
            token = tokenizer.next();

            continue :state token.tag;
        },

        // TODO create a list of valid tags
        else => |tag| {
            const slice = self.input[offset + token.loc.start .. offset + token.loc.end];

            const next = tokenizer.next();

            switch (next.tag) {
                // ...(... - implicit multiplication; previous token must be a variable or number
                .l_paren => {
                    switch (tag) {
                        .number_literal,
                        .identifier,
                        => {
                            self.buffer.appendSliceAssumeCapacity(slice);
                            self.buffer.appendSliceAssumeCapacity("*(");

                            before = .l_paren;
                            token = tokenizer.next();
                            continue :state token.tag;
                        },

                        else => {},
                    }
                },

                // ...!=... (!, =) -  ...)!, <number>! and <identifier>! are factorials
                .bang, .bang_equal => switch (token.tag) {
                    .r_paren => {
                        const factorial = "factorial";
                        if (parens_idx == null) return error.ParenthesisNotOpened;

                        var previous_len = self.buffer.items.len;
                        self.buffer.items.len += factorial.len;

                        // parens_idx is the index of the first character _inside_ the parenthesis opened most recently.
                        @memmove(self.buffer.items[parens_idx.? + factorial.len - 1 ..], self.buffer.items[parens_idx.? - 1 .. previous_len]);
                        @memcpy(self.buffer.items[parens_idx.? - 1 .. parens_idx.? + factorial.len - 1], factorial);

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

                    .number_literal,
                    .identifier,
                    .string_literal,
                    => {
                        self.buffer.appendSliceAssumeCapacity("factorial(");
                        self.buffer.appendSliceAssumeCapacity(slice);
                        self.buffer.appendSliceAssumeCapacity(")==");

                        before = .r_paren;
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
    const input = "x(x - 1)";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess6" {
    const input = "🐈(🐈 - 1)";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess7" {
    const input = "(x - 1)(x + 1)";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

const std = @import("std");
const parser = @import("parser");

const testing = std.testing;
const Parser = parser.Parser;
