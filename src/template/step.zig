pub fn Step(comptime T: type) type {
    switch (T) {
        f16, f32, f64, f128 => {},
        else => @compileError("cannot use type " ++ @typeName(T) ++ " as a generic argument for `Expression`"),
    }

    return struct {
        const Self = @This();

        before: *const Expression(T),
        after: ?*const Expression(T),
        description: []const u8,
        substeps: []const *Self,
    };
}

const Expression = @import("expr").Expression;
