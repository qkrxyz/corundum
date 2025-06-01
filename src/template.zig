pub const Kind = enum {
    identity,
    structure,
    dynamic,
};

/// The bindings a template has.
///
/// ---
/// ## Examples
/// The quadratic formula (`ax^2 + bx + c`) has four bindings:
///
/// - `a`, `b` and `c` are most commonly numbers (or fractions),
/// - `x` can be anything.
///
/// Therefore, the bindings `2x^2 + 3x - 4` has is equal to
/// ```zig
/// .{
///     .a = &Expression(T){ .number = 2.0 },
///     .b = &Expression(T){ .number = 3.0 },
///     .c = &Expression(T){ .number = -4.0 },
///     .x = &Expression(T){ .variable = "x" },
/// }
/// ```
///
/// and the sine function (`sin(x)`) has one binding, `x`, which is either:
/// - an unary operation (`.degree`) with an operand of type `number`/`fraction`,
/// - a number/fraction (implicitly interpreted as radians).
///
/// Note that when using `sin(x)`, π is represented as a variable.
///
/// Therefore, the bindings `sin(π/3)` has is equal to
/// ```zig
/// .{
///     .x = &Expression(T){ .fraction = .{
///         .numerator = .{ .variable = "π" },
///         .denominator = .{ .number = 3.0 },
///     } },
/// }
/// ```
pub fn Bindings(comptime Key: type, T: type) type {
    return std.EnumMap(Key, *const Expression(T));
}

/// A mathematical template/identity that can be solved.
///
/// A template is one of:
/// - an identity (well-defined AST, has a proof),
/// - a structure (allows for parameters of a given type),
/// - a dynamic template (doesn't have an AST).
pub fn Template(comptime Key: type, comptime T: type) type {
    switch (T) {
        f16, f32, f64, f128 => {},
        else => @compileError("cannot use type " ++ @typeName(T) ++ " as a generic argument for `Expression`"),
    }

    return union(Kind) {
        /// A mathematical identity that has only one form (AST) and has a proof.
        ///
        /// Matched by the engine according to the AST's full hash.
        identity: struct {
            name: []const u8,
            ast: Expression(T),
            proof: fn () anyerror!Solution(T),
        },

        /// A mathematical template that allows for templated variables of a given type.
        ///
        /// For example, number addition is classified as a "structure" since you can only use numbers
        /// as parameters, therefore the AST would look like this:
        /// ```zig
        /// const number_addition = Expression(T) { .binary = .{
        ///     .left = &.{ .templated = .number },
        ///     .right = &.{ .templated = .number },
        ///     .operation = .addition,
        /// } };
        /// ```
        ///
        /// It gets matched by the engine by the AST's structural hash.
        structure: struct {
            name: []const u8,
            ast: Expression(T),
            matches: fn (*const Expression(T)) anyerror!Bindings(Key, T),
            solve: fn (*const Expression(T), Bindings(Key, T), std.mem.Allocator) anyerror!Solution(T),
        },

        /// A dynamic template that doesn't have a concrete representation.
        ///
        /// For example, division by zero can't be represented by an AST, since you
        /// can divide anything by zero - any one of these is "division by zero":
        ///
        /// - `1/0`
        /// - `x/0`
        /// - `((21 * 37) + 420)/0`
        ///
        /// It gets matched by the engine according to the result of `matches`.
        dynamic: struct {
            name: []const u8,
            matches: fn (*const Expression(T)) anyerror!Bindings(Key, T),
            solve: fn (Bindings(Key, T), std.mem.Allocator) anyerror!Solution(T),
        },
    };
}

const std = @import("std");

const expr = @import("expr");
pub const Templates = @import("templates").templates;

const Expression = expr.Expression;
pub const Solution = @import("template/solution").Solution;
pub const Step = @import("template/step").Step;
