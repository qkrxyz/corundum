/// The kind of an `Expression`.
pub const Kind = enum {
    number,
    variable,
    boolean,
    fraction,
    equation,
    binary,
    unary,
    function,
    templated,
};

/// A mathematical expression, like `x`, `3.14` or `30°`.
pub fn Expression(T: type) type {
    switch (T) {
        f16, f32, f64, f128 => {},
        else => @compileError("cannot use type " ++ @typeName(T) ++ " as a generic argument for `Expression`"),
    }

    return union(Kind) {
        const Self = @This();

        number: T,
        variable: []u8,
        boolean: bool,
        fraction: struct {
            numerator: *const Self(T),
            denominator: *const Self(T),
        },
        equation: struct {
            left: *const Self(T),
            right: *const Self(T),
            sign: enum {
                equals,
                not_equals,
                more,
                more_or_eq,
                less,
                less_or_eq,
            },
        },
        binary: struct {
            left: *const Self(T),
            right: *const Self(T),
            operation: enum {
                addition,
                subtraction,
                multiplication,
                division,
                exponentiation,
            },
        },
        unary: struct {
            operand: *const Self(T),
            operation: enum {
                degree,
                negation,
                factorial,
            },
        },
        function: struct {
            name: []u8,
            arguments: []*const Self(T),
            body: ?*const Self(T),
        },
        templated: Kind,

        pub fn hash(self: *const Self) u64 {
            var hasher = std.hash.XxHash64.init(0);
            hash_impl(T, self, &hasher);
            return hasher.final();
        }
    };
}

const std = @import("std");

const hash_impl = @import("expr/hash").hash;
