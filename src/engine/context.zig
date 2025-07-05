pub const Language = enum {
    en_US,
    pl_PL,
};

pub fn Context(comptime T: type) type {
    const pow10 = struct {
        fn pow10(x: usize) T {
            var result: T = 10.0;
            for (0..x + 1) |_| {
                result *= 10.0;
            }

            return result;
        }
    }.pow10;

    const npow10 = struct {
        fn npow10(x: usize) T {
            var result: T = 10.0;
            for (0..x + 1) |_| {
                result /= 10.0;
            }

            return result;
        }
    }.npow10;

    return struct {
        const Self = @This();

        language: Language,
        functions: struct {
            pow10: *const fn (x: usize) T,
            npow10: *const fn (x: usize) T,
        },
        variables: *std.StringHashMap(*const Expression(T)),

        pub fn init(
            language: Language,
            variables: *std.StringHashMap(*const Expression(T)),
        ) Self {
            return Self{
                .language = language,
                .functions = .{
                    .pow10 = pow10,
                    .npow10 = npow10,
                },
                .variables = variables,
            };
        }

        pub fn find_variants(
            self: *const Self,
            comptime Kind: template.TemplatesKind,
            expression: *const Expression(T),
            allocator: std.mem.Allocator,
        ) std.mem.Allocator.Error!?Solution(T) {
            const variants = comptime template.Templates.variants(Kind, T);
            inline for (variants) |variant| {
                if (variant.matches(expression)) |bindings| {
                    const result: ?Solution(T) = try variant.solve(expression, bindings, self.*, allocator);
                    return result;
                } else |_| {}
            }

            return null;
        }

        pub fn find_templates(
            self: *const Self,
            comptime name: []const u8,
            expression: *const Expression(T),
            allocator: std.mem.Allocator,
        ) std.mem.Allocator.Error!?Solution(T) {
            inline for (template.Templates.contains(name)) |kind| {
                const resolved = template.Templates.resolve(kind, T);

                switch (resolved) {
                    .@"n-ary" => |n_ary| {
                        const new_bindings = n_ary.matches(expression, allocator);

                        if (new_bindings) |b| {
                            defer allocator.free(b);

                            const result: ?Solution(T) = try n_ary.solve(expression, b, self.*, allocator);
                            return result;
                        } else |_| {}
                    },

                    .dynamic => |dynamic| {
                        const new_bindings = dynamic.matches(expression);

                        if (new_bindings) |b| {
                            const result: ?Solution(T) = try dynamic.solve(expression, b, self.*, allocator);
                            return result;
                        } else |_| {}
                    },

                    .structure => |structure| {
                        if (structure.matches(expression)) |b| {
                            const result: ?Solution(T) = try structure.solve(expression, b, self.*, allocator);
                            return result;
                        } else |_| {}
                    },

                    .identity => |identity| {
                        if (expression.hash() == comptime identity.ast.hash()) {
                            const result: ?Solution(T) = identity.proof(self.*);
                            return result;
                        }
                    },
                }
            }

            return null;
        }

        pub fn deinit(self: *const Self) void {
            self.variables.deinit();
        }
    };
}

const std = @import("std");
const expr = @import("expr");
const template = @import("template");

const Expression = expr.Expression;
const Solution = template.Solution;
