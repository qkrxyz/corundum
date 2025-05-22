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
            numerator: *Expression(T),
            denominator: *Expression(T),
        },
        equation: struct {
            left: *Expression(T),
            right: *Expression(T),
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
            left: *Expression(T),
            right: *Expression(T),
            operation: enum {
                addition,
                subtraction,
                multiplication,
                division,
                exponentiation,
            },
        },
        unary: struct {
            operand: *Expression(T),
            operation: enum {
                degree,
                negation,
                factorial,
            },
        },
        function: struct {
            name: []u8,
            arguments: []*Expression(T),
            body: ?*Expression(T),
        },
        templated: Kind,
    };
}
