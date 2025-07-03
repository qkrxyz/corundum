const std = @import("std");

pub fn asBytes(comptime input: []const u21) [input.len][4]u8 {
    comptime var result: [input.len][4]u8 = undefined;
    for (input, 0..) |codepoint, i| {
        const bytes: []const u8 = std.mem.asBytes(codepoint);
        result[i] = bytes;
    }
    return result;
}

pub const Disallowed: []const u21 = &[_]u21{
    0x2028, 0x2029, // line/paragraph separators
};

pub const Whitespace: []const u21 = &[_]u21{
    0x20, 0x09, 0x0D, 0x0A, // ascii
    0xA0, // NBSP
    0x1680, // ogham space mark
    0x180E, // mongolian vowel separator
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x200B, 0x200C, 0x200D, // en/em/other quads and spaces/joiners
    0x202F, // narrow no-break space
    0x205F, // medium mathematical space
    0x2060, // word joiner
    0x3000, // ideographic space
    0xFEFF, // zero width non-breaking space
};

pub const Separator: []const u21 = &[_]u21{
    ',',
    '.',
    0x066B,
    0x066C, // arabic decimal separators
    0x2E12, // hypodiastole
    0x2E32,
    0x2E34, // turned & raised commas
    0x2E41, // reversed comma
    0x2E47, // low kavyka
    0x3001, 0x3002, // ideographic comma/full stop
    0xFE45, // sesame dot
    0xFE50, 0xFE51, 0xFE52, // small (ideographic) comma, small full stop
    0xFF61, // halfwidth ideographic full stop
    0xFF0C, // fullwidth comma
    0xFF0E, // fullwidth full stop
    0x10101, // aegean word separator dot
    0x1091F, // phoenician word separator
    0x111C8, // sharada separator
    0x16E97, 0x16E98, // medefaidrin comma/full stop
};

// TODO: https://www.compart.com/en/unicode/category/Sm
pub const Math = struct {
    pub const codepoint: []const u21 = &[_]u21{
        '1', '2', '3', '4', '5', '6', '7', '8', '9', // numbers
        '+', '*', '/', '<', '=', '>', '|', '~', '!',
        '(', ')',
    };

    pub const ascii: []const u8 = &[_]u8{
        '1', '2', '3', '4', '5', '6', '7', '8', '9', // numbers
        '+', '*', '/', '<', '=', '>', '|', '~', '!',
        '(', ')',
    };
};

pub const RewriteData = struct { original: u21, rewrite: []const u8 };

pub const RewriteInPlace = struct {
    pub const inner: []const RewriteData = &.{
        .{ .original = 0x00D7, .rewrite = "*" }, // multiplication
        .{ .original = 0x00F7, .rewrite = "/" }, // division
        .{ .original = 0x2044, .rewrite = "/" }, // fraction slash
        .{ .original = 0x2205, .rewrite = "emptyset()" }, // empty set
        .{ .original = 0x2212, .rewrite = "-" }, // minus sign
        .{ .original = 0x2215, .rewrite = "/" }, // division slash
        .{ .original = 0x2217, .rewrite = "*" }, // asterisk operator
        .{ .original = 0x221E, .rewrite = "infinity()" }, // infinity
        .{ .original = 0x2227, .rewrite = "and" }, // logical and
        .{ .original = 0x2228, .rewrite = "or" }, // logical or
        .{ .original = 0x2264, .rewrite = "<=" }, // less than or equal to
        .{ .original = 0x2265, .rewrite = ">=" }, // greater than or equal to
        .{ .original = 0x2295, .rewrite = "+" }, // circled plus
        .{ .original = 0x2296, .rewrite = "-" }, // circled minus
        .{ .original = 0x2297, .rewrite = "*" }, // circled times
        .{ .original = 0x2298, .rewrite = "/" }, // circled division slash
        .{ .original = 0x229B, .rewrite = "*" }, // circled asterisk operator
        .{ .original = 0x229C, .rewrite = "=" }, // circled equals
        .{ .original = 0x229D, .rewrite = "-" }, // circled dash
        .{ .original = 0x229E, .rewrite = "+" }, // squared plus
        .{ .original = 0x229F, .rewrite = "-" }, // squared minus
        .{ .original = 0x22A0, .rewrite = "*" }, // squared times
    };

    pub const codepoints = blk: {
        var result: [inner.len]u21 = undefined;
        for (inner, 0..) |data, i| {
            result[i] = data.original;
        }
        break :blk result;
    };

    pub const replacements = blk: {
        var result: [inner.len][]u8 = undefined;
        for (inner, 0..) |data, i| {
            result[i] = data.rewrite;
        }
        break :blk result;
    };
};
