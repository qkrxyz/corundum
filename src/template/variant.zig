/// A variant of a template.
///
/// In general, variants provide more specific and precise solutions that utilize properties otherwise not applicable.
/// When the parent of this variant gets matched, the engine goes through all variants to see if there are any matches.
pub fn Variant(comptime Key: type, comptime T: type) type {
    switch (T) {
        f16, f32, f64, f128 => {},
        else => @compileError("cannot use type " ++ @typeName(T) ++ " as a generic argument for `Variant`"),
    }

    return struct {
        name: []const u8,
        matches: *const fn (*const Expression(T)) anyerror!Bindings(Key, T),
        solve: *const fn (*const Expression(T), Bindings(Key, T), std.mem.Allocator) anyerror!Solution(T),
        score: usize,
    };
}

const std = @import("std");
const expr = @import("expr");
const template = @import("template");

const Template = template.Template;
const Bindings = template.Bindings;
const Solution = template.Solution;
const Expression = expr.Expression;
