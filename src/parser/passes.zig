pub fn factorial(
    comptime T: type,
    start_idx: usize,
    self: *parser.Parser(T),
    next: std.zig.Token,
) !std.zig.Token.Tag {
    const factorial_string = "factorial(";

    var previous_len = self.buffer.items.len;
    self.buffer.items.len += factorial_string.len;

    @memmove(self.buffer.items[start_idx + factorial_string.len ..], self.buffer.items[start_idx..previous_len]);
    @memcpy(self.buffer.items[start_idx .. start_idx + factorial_string.len], factorial_string);

    previous_len = self.buffer.items.len;

    if (next.tag == .bang_equal) {
        self.buffer.items.len += 3;

        @memcpy(self.buffer.items[previous_len..self.buffer.items.len], ")==");
        return .equal;
    } else {
        self.buffer.items.len += 1;

        @memcpy(self.buffer.items[previous_len..self.buffer.items.len], ")");
        return .r_paren;
    }
}

pub fn derivative(
    comptime T: type,
    self: *parser.Parser(T),
    indices: std.EnumMap(preprocess.ExprType, usize),
) !void {
    const beginning = indices.get(.function) orelse return error.InvalidDerivative;

    const derivative_string = "derivative(";

    const previous_len = self.buffer.items.len;

    self.buffer.items.len += derivative_string.len;

    @memmove(self.buffer.items[beginning + derivative_string.len ..], self.buffer.items[beginning..previous_len]);
    @memcpy(self.buffer.items[beginning .. beginning + derivative_string.len], derivative_string);
    self.buffer.appendAssumeCapacity(')');
}

const std = @import("std");
const parser = @import("parser");
const preprocess = @import("parser/preprocess");
