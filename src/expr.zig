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
            numerator: *const Self,
            denominator: *const Self,
        },
        equation: struct {
            left: *const Self,
            right: *const Self,
            sign: Sign,
        },
        binary: struct {
            left: *const Self,
            right: *const Self,
            operation: BinaryOperation,
        },
        unary: struct {
            operand: *const Self,
            operation: UnaryOperation,
        },
        function: struct {
            name: []u8,
            arguments: []*const Self,
            body: ?*const Self,
        },
        templated: Kind,

        pub const Sign = enum {
            equals,
            not_equals,
            more,
            more_or_eq,
            less,
            less_or_eq,
        };
        pub const BinaryOperation = enum {
            addition,
            subtraction,
            multiplication,
            division,
            exponentiation,
        };
        pub const UnaryOperation = enum {
            degree,
            negation,
            factorial,
        };

        pub fn hash(self: *const Self) u64 {
            var hasher = std.hash.XxHash64.init(0);
            hash_impl(T, self, &hasher);
            return hasher.final();
        }

        pub fn structural(self: *const Self) u32 {
            var hasher = std.hash.XxHash32.init(0);
            structural_impl(T, self, &hasher);
            return hasher.final();
        }
    };
}

const std = @import("std");

const hash_impl = @import("expr/hash").hash;
const structural_impl = @import("expr/structural").structural;
