pub fn Solution(comptime T: type) type {
    switch (T) {
        f16, f32, f64, f128 => {},
        else => @compileError("cannot use type " ++ @typeName(T) ++ " as a generic argument for `Expression`"),
    }

    return struct {
        steps: []Step(T),
    };
}

const Step = @import("template/step").Step;
