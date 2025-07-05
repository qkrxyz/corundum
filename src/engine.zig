pub fn Engine(comptime T: type) type {
    const Parser = @import("parser").Parser;

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        input: [:0]const u8,

        pub fn init(allocator: std.mem.Allocator, input: [:0]const u8) Self {
            return Self{
                .allocator = allocator,
                .input = input,
            };
        }

        pub fn run(self: *const Self) !Solution(T) {
            const parser = Parser(T);

            const preprocessed = try parser.preprocess(self.input, self.allocator);
            defer self.allocator.free(preprocessed);

            const result = try parser.parse(preprocessed, self.allocator);
            defer {
                result.expression.deinit(self.allocator);
            }

            const context = Context(T).init(.en_US, result.variables);

            // TODO improve the engine ofc
            inline for (template.Templates.all()) |kind| {
                const resolved = template.Templates.resolve(kind, T);

                switch (resolved) {
                    .@"n-ary" => |n_ary| {
                        const bindings = n_ary.matches(result.expression, self.allocator);

                        if (bindings) |b| {
                            defer self.allocator.free(b);

                            const solution = try n_ary.solve(result.expression, b, context, self.allocator);
                            return solution;
                        } else |_| {}
                    },

                    .dynamic => |dynamic| {
                        const bindings = dynamic.matches(result.expression);

                        if (bindings) |b| {
                            const solution = try dynamic.solve(result.expression, b, context, self.allocator);
                            return solution;
                        } else |_| {}
                    },

                    .structure => |structure| {
                        if (result.expression.structural() == comptime structure.ast.structural()) {
                            if (structure.matches(result.expression)) |bindings| {
                                const solution = try structure.solve(result.expression, bindings, context, self.allocator);
                                return solution;
                            } else |_| {}
                        }
                    },

                    .identity => |identity| {
                        if (result.expression.hash() == comptime identity.ast.hash()) {
                            const solution = identity.proof(context);
                            return solution;
                        }
                    },
                }
            }

            return error.NoTemplateFound;
        }
    };
}

const std = @import("std");
const expr = @import("expr");
const template = @import("template");

pub const Context = @import("engine/context").Context;
const Solution = template.Solution;
