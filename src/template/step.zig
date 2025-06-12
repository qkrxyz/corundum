pub fn Step(comptime T: type) type {
    switch (T) {
        f16, f32, f64, f128 => {},
        else => @compileError("cannot use type " ++ @typeName(T) ++ " as a generic argument for `Step`"),
    }

    return struct {
        const Self = @This();

        before: *const Expression(T),
        after: ?*const Expression(T),
        description: []const u8,
        substeps: []*const Self,

        pub fn clone(self: Self, allocator: std.mem.Allocator) !*const Self {
            const result = try allocator.create(Self);

            result.* = self;
            return result;
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            self.before.deinit(allocator);
            if (self.after) |after| after.deinit(allocator);

            allocator.free(self.description);

            for (self.substeps) |step| {
                step.deinit(allocator);
            }

            allocator.free(self.substeps);
            allocator.destroy(self);
        }
    };
}

const std = @import("std");

const Expression = @import("expr").Expression;
