pub fn Solution(comptime T: type) type {
    switch (T) {
        f16, f32, f64, f128 => {},
        else => @compileError("cannot use type " ++ @typeName(T) ++ " as a generic argument for `Solution`"),
    }

    return struct {
        const Self = @This();

        steps: []*const Step(T),

        pub fn init(len: usize, allocator: std.mem.Allocator) !Self {
            return Self{ .steps = try allocator.alloc(*const Step(T), len) };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            for (self.steps) |step| {
                step.deinit(allocator);
            }

            allocator.free(self.steps);
        }
    };
}

const std = @import("std");

const Step = @import("template/step").Step;
