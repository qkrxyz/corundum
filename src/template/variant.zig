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
        matches: fn (*const Expression(T)) anyerror!Bindings(Key, T),
        solve: fn (*const Expression(T), Bindings(Key, T), Context(T), std.mem.Allocator) std.mem.Allocator.Error!Solution(T),
        score: usize,
    };
}

const std = @import("std");
const expr = @import("expr");
const template = @import("template");
const engine = @import("engine");

const Context = engine.Context;
const Template = template.Template;
const Bindings = template.Bindings;
const Solution = template.Solution;
const Expression = expr.Expression;
