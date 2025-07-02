pub const ExprType = enum {
    parens,
    identifier,
    function,
};

pub fn preprocess(comptime T: type, self: *Parser(T), comptime pre: []const u8, comptime post: []const u8) !void {
    // the maximum additional count of characters these characters require.
    // equals, degree, factorial, unicode characters, implicit multiplication, derivation.
    const costs: @Vector(6, usize) = .{ 1, 7, 10, 3, 1, 11 };

    // equals, degree, factorial, unicode characters, implicit multiplication, derivation.
    var counts: @Vector(6, usize) = .{ 0, 0, 0, 0, 0, 1 };

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

            '!' => {
                @branchHint(.unlikely);

                counts[2] += 1;
            },

            '\'' => {
                @branchHint(.unlikely);

                counts[3] += 1;
            },

            // standard ASCII characters
            0x9...0xA,
            0xD,
            0x20,
            0x22...0x26,
            0x28,
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

    var tokenizer = std.zig.Tokenizer.init(self.input);

    var before: ?std.zig.Token.Tag = null;
    var indices: std.EnumMap(ExprType, usize) = .init(.{});
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

                const invalid = @reduce(
                    .Or,
                    @as(@Vector(l18n.Disallowed.len, u21), @splat(codepoint)) == l18n.asVector(u21, l18n.Disallowed),
                );
                if (invalid) return error.InvalidCharacter;

                const skippable_data = l18n.Whitespace ++ l18n.Separator ++ l18n.Math.codepoint;
                const skippable = l18n.asVector(u21, skippable_data);

                const should_break = @reduce(
                    .Or,
                    @as(@Vector(skippable_data.len, u21), @splat(codepoint)) == skippable,
                );
                if (should_break) break;

                end_idx += len;
            }

            if (before != .identifier) {
                indices.put(.identifier, self.buffer.items.len);
                self.buffer.appendSliceAssumeCapacity("@\"");
            }
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

                .bang, .bang_equal => {
                    self.buffer.appendSliceAssumeCapacity(self.input[offset + token.loc.start .. offset + token.loc.end]);
                    before = try passes.factorial(T, self.buffer.items.len - token.loc.end + token.loc.start, self, next);

                    token = tokenizer.next();

                    continue :state token.tag;
                },

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

            if (before != null) switch (before.?) {
                // ...!
                .number_literal, .identifier => {
                    before = try passes.factorial(T, indices.getAssertContains(.identifier), self, next);

                    token = tokenizer.next();

                    continue :state token.tag;
                },

                else => {},
            };

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
            @branchHint(.likely);

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
            @branchHint(.likely);

            const next = tokenizer.next();

            switch (next.tag) {
                // ...!=... (!, =) -  ...)!, <number>! and <identifier>! are factorials
                .bang, .bang_equal => {
                    const parens = indices.get(.parens) orelse return error.ParenthesisNotOpened;

                    @memmove(self.buffer.items[parens - 1 .. self.buffer.items.len - 1], self.buffer.items[parens..self.buffer.items.len]);
                    self.buffer.items.len -= 1;
                    before = try passes.factorial(T, parens - 1, self, next);

                    token = tokenizer.next();

                    continue :state token.tag;
                },

                .invalid, .char_literal => if (self.input[offset + next.loc.start] == '\'') {
                    // derivatives
                    self.buffer.appendAssumeCapacity(')');
                    try passes.derivative(T, self, indices);

                    if (offset + token.loc.start + 2 >= self.input.len) continue :state .eof;
                    indices.remove(.function);

                    tokenizer = std.zig.Tokenizer.init(self.input[offset + token.loc.start + 2 .. self.input.len :0]);
                    offset += token.loc.start + 2;

                    token = tokenizer.next();

                    continue :state token.tag;
                },

                else => {},
            }

            self.buffer.appendAssumeCapacity(')');

            before = .r_paren;
            token = next;

            continue :state token.tag;
        },

        .char_literal => {
            // derivatives
            try passes.derivative(T, self, indices);

            if (offset + token.loc.start + 2 >= self.input.len) continue :state .eof;
            indices.remove(.function);

            tokenizer = std.zig.Tokenizer.init(self.input[offset + token.loc.start + 2 .. self.input.len :0]);
            offset += token.loc.start + 2;

            token = tokenizer.next();

            continue :state token.tag;
        },

        // TODO create a list of valid tags
        else => |tag| {
            @branchHint(.likely);

            const slice = self.input[offset + token.loc.start .. offset + token.loc.end];

            const next = tokenizer.next();

            switch (next.tag) {
                .bang, .bang_equal => switch (token.tag) {
                    // TODO separate this into its own branch outside of else
                    .number_literal,
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

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

test "preprocess6" {
    const input = "🐈(🐈 + 1)";

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

test "preprocess8" {
    const input = "ogórek = 3";

    var p = Parser(f64).init(input[0..input.len :0], testing.allocator);
    defer p.deinit();

    try p.preprocess();

    std.debug.print("before: `{s}`\nafter: `{s}`\n", .{ input, p.buffer.items });
}

const std = @import("std");
const parser = @import("parser");
const passes = @import("parser/passes");

const testing = std.testing;
const Parser = parser.Parser;
const l18n = @import("parser/l18n");
