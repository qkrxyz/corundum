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
    parenthesis,
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
        variable: []const u8,
        boolean: bool,

        /// `\frac{numerator}{denominator}`
        fraction: struct {
            numerator: *const Self,
            denominator: *const Self,
        },

        /// `left sign right`
        equation: struct {
            sign: Sign,
            left: *const Self,
            right: *const Self,
        },

        /// Two operands - `left operation right`
        binary: struct {
            operation: BinaryOperation,
            left: *const Self,
            right: *const Self,
        },

        /// One operand - `operation operand`
        unary: struct {
            operation: UnaryOperation,
            operand: *const Self,
        },

        /// `name(arguments) = body`
        function: struct {
            body: ?*const Self,
            name: []const u8,
            arguments: []*const Self,

            pub inline fn create(name: []const u8, arguments: []*const Self) Self {
                return Self{ .function = .{
                    .name = name,
                    .arguments = arguments,
                } };
            }
        },

        /// Represents the expression kind this expression is a placeholder for.
        templated: Kind,

        /// `(expr)`
        parenthesis: *const Expression(T),

        pub const Sign = enum(u8) {
            /// `=`
            equals,

            /// `!=`
            not_equals,

            /// `>`
            more,

            /// `>=`
            more_or_eq,

            /// `<`
            less,

            /// `<=`
            less_or_eq,
        };

        pub const BinaryOperation = enum {
            /// `+`
            addition,

            /// `-`
            subtraction,

            /// `*`
            multiplication,

            /// `/`
            division,

            /// `^`
            exponentiation,

            /// `%`
            modulus,
        };

        pub const UnaryOperation = enum {
            /// `°`
            degree,

            /// `-`
            negation,

            /// `!`
            factorial,
        };

        /// Create a new expression.
        pub fn init(input: Self, allocator: std.mem.Allocator) !*const Self {
            return clone(&input, allocator);
        }

        /// Compute the hash of this expression.
        ///
        /// Uses XxHash64.
        pub fn hash(self: *const Self) u64 {
            var hasher = std.hash.XxHash64.init(0);
            hash_impl(T, self, &hasher);
            return hasher.final();
        }

        /// Compute the structural hash of this expression.
        ///
        /// This means that `2 + 3` is equivalent to `4 + 5`, but both have
        /// different hashes than `x + 2`.
        ///
        /// Uses XxHash32.
        pub fn structural(self: *const Self) u32 {
            var hasher = std.hash.XxHash32.init(0);
            structural_impl(T, self, &hasher);
            return hasher.final();
        }

        /// Creates a deep clone of this expression.
        pub fn clone(self: *const Self, allocator: std.mem.Allocator) !*const Self {
            return clone_impl(T, self, allocator);
        }

        /// Frees the memory associated with this expression.
        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .number, .boolean, .templated => {},
                .variable => |variable| allocator.free(variable),
                .fraction => |fraction| {
                    fraction.numerator.deinit(allocator);
                    fraction.denominator.deinit(allocator);
                },
                .equation => |equation| {
                    equation.left.deinit(allocator);
                    equation.right.deinit(allocator);
                },
                .binary => |binary| {
                    binary.left.deinit(allocator);
                    binary.right.deinit(allocator);
                },
                .unary => |unary| {
                    unary.operand.deinit(allocator);
                },
                .function => |function| {
                    allocator.free(function.name);

                    for (function.arguments) |argument| {
                        argument.deinit(allocator);
                    }
                    allocator.free(function.arguments);

                    if (function.body) |body| body.deinit(allocator);
                },
                .parenthesis => |inner| inner.deinit(allocator),
            }

            allocator.destroy(self);
        }
    };
}

const std = @import("std");

const hash_impl = @import("expr/hash").hash;
const structural_impl = @import("expr/structural").structural;
const clone_impl = @import("expr/clone").clone;
