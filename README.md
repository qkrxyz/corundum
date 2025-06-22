# corundum

A scalable, "simple" and fast math engine with step-by-step instructions, written in [Zig](https://github.com/ziglang/zig).

## Roadmap

- [x] ~~Basic expressions, templates and solutions~~
- [x] ~~Template variants~~
- [x] ~~Basic arithmetic templates (number addition, subtration, division) with high quality step-by-step solutions~~
- [ ] Number division, exponentiation
- [ ] Builtin functions - square root, logarithms, etc.
- [ ] __Refactor__ change everything to utilize `.zon` files for metadata/static strings and be l18n/i10n ready, along with expanded test coverage
- [ ] __Refactor__ add arbitrary precision
- [x] ~~Template scoring~~
- [x] ~~A working prototype of a web app that utilizes this engine~~
- [ ] Implement fractions and equations, __refactor__ division to use fractions where possible
- [ ] Add basic algebra support
- [ ] Add "actions"
- [ ] Custom templates written in `.zon` and formatting support (in LaTeX, [typst](https://github.com/typst/typst), etc.)

## How does it work?

### Architecture

The engine relies on "templates", which are self-contained rewrite rules consisting of at least two things:

- a `.matches` function - processes the AST and returns the necessary "bindings" (variables in a given template),
- a `.solve` function - solves the expression with the help of bindings.

A template can also have "variants", which are more specific
(i.e. number multiplication - when given $0.5 \times 3$, the most textbook way to do it is to multiply $3$ by the decimal part of $0.5$, and shift the result left by 1 decimal place, since there is 1 digit after the decimal).

The most essential part of these rewrite rules are expressions, which are represented by `Expression(T)` - a tagged union that is generic over the type `T`, which is used as the number type.
Currently, you can only use `f16`, `f32`, `f64` and `f128` (support for arbitrary precision (~~[`std.math.big.int`](https://ziglang.org/documentation/master/std/#std.math.big.int)~~ [big integers](https://ziglang.org/documentation/master/#Integers)) is coming!).

### Engine

At build time, the `build.zig` script iterates over all file entries in the [templates](./templates/) directory, which get added to a central inventory (similar to the [`inventory`](https://crates.io/crates/inventory) crate in Rust).
After that, you can use them by calling `template.Templates.get` or `template.Templates.all` to get them all.

At runtime, the engine iterates over all _templates_ (the engine also collects variants, but they are excluded from `template.Templates.all`), sorts them according to their "score" contained in a `metadata.zon` file (e.g. $2 + 3$ would first match to `core/number/addition` rather than `core/number/n-ary/addition`, since all templates in `core/number` have a higher score than `core/number/n-ary`) and does different things according to the template kind:

If the template is an __identity__:

1. Compare full expression hashes (`expression.hash() == comptime identity.ast.hash()`)
2. If they are equal, return the proof for this. This "proof" (that is a solution) isn't heap-allocated (because of the previous step; there is only one expression that matches), which means that this step is "free".

If the template is a __structural template__:

1. Compare structural expression hashes (`expression.structural() == comptime structural.ast.structural()`) and if they are equal, call the `.solve` function. (Next steps are an outline of how `.solve` works)
2. Iterate over all variants, and call `.matches` on them (since they need to have the same AST as the parent, but different requirements).
3. If there is a variant match, replace the generic solution with the specialized one. If not, proceed with the generic solution.

If the template is a __dynamic template__:

1. Call the `.matches` function, which checks the expression if it matches (e.g. for $1 + 2 + 3 + 4$, `.matches` recursively calls itself to check if it can flatten the AST - there is no way anyone is writing an infinite amount of templates just to match $1 + 2 + 3 + ... + 99$).
2. _same as the structural template, from step #2 onwards_

### Actions

A template can have its own actions, which can be treated as "templates" but are considered by the engine as a second line of defense. If there are no matching templates, the engine tries to apply an action (creating a separate path for it) and tries again to find a matching template. If that fails, the entire process happens again, but this time only for subexpressions (and again tries to match the entire expression).

This trigonometric proof is a great example of this:

$\frac{1 + 2sin(x)cos(x)}{cos^2(x)} = (1 + tg(x))^2$
$L = \frac{1 + 2sin(x)cos(x)}{cos^2(x)} = \frac{sin^2(x) + cos^2(x) + 2sin(x)cos(x)}{cos^2(x)} = \frac{(sin(x) + cos(x))^2}{cos^2(x)}$
$R = (1 + tg(x))^2 = 1 + 2tg(x) + tg^2(x) = 1 + \frac{2sin(x)}{cos(x)} + \frac{sin^2(x)}{cos^2(x)} = \frac{cos^2(x)}{cos^2(x)} + \frac{2sin(x)}{cos(x)} + \frac{sin^2(x)}{cos^2(x)} = \frac{sin^2(x) + 2sin(x)cos(x) + cos^2(x)}{cos^2(x)} = \frac{(sin(x) + cos(x))^2}{cos^2(x)}$

Here, the engine would get "stuck" and try to apply an action for the $1$ in the numerator of the left side. It would notice that $1 = sin^2(x) + cos^2(x)$, and try again to match the entire expression. It would again fail, and this time notice that $sin^2(x) + cos^2(x) + 2sin(x)cos(x)$ can be reordered to form a perfect square, which can be simplified.

On the right side, it would expand $(1 + tg(x))^2$ (or replace $tg(x)$ with $\frac{sin(x)}{cos(x)}$, both options work) and eventually arrive at the same expression as the left side, which means that the equality holds.

The engine can also take a different route: it can interpret this as a trigonometric equation and move everything to the left side, which after the same simplifications would result in $x \in \mathbb{R}$.

### Upcoming features

#### Arbitrary precision

To avoid the infamous $0.1 + 0.2 = 0.3000004...$ "bug", `corundum` will receive a new type, called `Number(T)`. It can either take in a floating-point integer (so `f16`, `f32`, `f64` or `f128`) or a big integer (e.g. `i512`). This means that `Number(T)` will look like this ("arbitrary" used since it's bigger than a `f128`):

```zig
pub const Kind = enum {
    fixed,
    arbitrary,
};

pub fn Number(comptime T: type) type {
    switch(@typeInfo(T)) {
        .float, .comptime_float => {},
        .int, .comptime_int => {},

        else => @compileError("..."),
    }

    return union(Kind) {
        const Self = @This();

        fixed: T,
        arbitrary: struct {
            value: T,
            decimal: isize,
        },

        // or combine them into one function with `anytype` that is either a float, or a tuple
        pub fn init_float(value: T) Self {
            return Self{ .fixed = value };
        }

        pub fn init_arbitrary(value: T, decimal: isize) Self {
            return Self{ .arbitrary = .{ .value = T, .decimal = isize } };
        }

        // ...
    };
}
```

and the `arbitrary` kind will work (almost) the same way `BigDecimal` does in Java: the value is actually $value \times 10^{decimal}$.

#### Custom templates

In order to have the end user be able to create and add their own templates without recompiling, I plan on adding "custom templates", which are written in ZON, _always_ are functions and (among metadata) contain steps necessary to compute the solution, as shown below:

```zon
.{
    .name = "Number average",

    .definition = .{
        .name = "average",

        .parameters = .{ .n_ary = .number },

        // or assuming we want this template to only work with 2 numbers (or other types):
        // .parameters = .{ .array = .{ .number, .number } },
        //
        // or simply an expression (Expression(T)):
        // .parameters = .{ .ast = ... },
        //
        // or even steal the bindings from another template:
        // .parameters = .{ .template = .@"..." },
    },

    // These are the contents the "bindings" would have for this template, assuming we have defined `parameters` as an n-ary.
    .inputs: .{ "array" },

    // In case your `parameters` is an AST, or an array:
    // .inputs = .{
    //     .keys = .{ "a", "b", ... },
    //     .paths = .{ "binary.left", ... },
    // },
    //
    // And if your `parameters` calls a template, define it the same way you'd normally do, but with the same keys.


    // These are the solution steps.
    // Currently, they only can call "builtin" templates (so only templates the engine always contains; it should probably stay this way).
    .solution = .{
        // Since we know that "array" is an array of numbers and this template expects to have a binding of the same type, be can bind it here. Otherwise, we need to figure out the proper way to convert it to the expected type.
        //
        // Here, if you use bindings from an AST, you'd simply call .@"core/n-ary/to function" before with your bindings.
        .{ .bind = "sum", .action = .@"core/number/n-ary/addition", .bindings = .{ .array = "array" } },

        // The same logic applies here. Since this template has keyed bindings, you also need to specify the key.
        .{ .bind = "length", .action = .@"core/n-ary/length", .bindings = .{ .keyed = .{ .function = "array" } } },

        // The last step will always represent a result.
        .{ .bind = "result", .action = .@"core/number/division", .bindings = .{ .keyed = .{ .a = "sum", .b = "length" } } },
    },
}
```

## Transparency report: AI usage

While creating this project, AI was involved in these changes/additions:

- migration from `std.StaticStringMap`/`std.StringHashMap` to `std.EnumMap` and enums in templates for type safety and optimizations
- iterating over the `templates` directory only once in `build.zig` - previously the build script created an empty file, iterated, created another file with the templates' data and overwrote the first one
- idea of "n-ary" (variadic) functions
- JS side of the WASM implementation

Whilst the LLM provided the code for these ideas, I decided to implement everything myself (for example: Claude suggested I try to use enums for bindings. I agreed and decided to add them, which also meant that I needed to spend a whole day trying to integrate them, since each template has different keys and therefore it's not as straightforward to iterate over them (or even collect them into a concrete type), see [build.zig](./build.zig). The idea eventually also "infected" the actual template inventory, which now also uses a `std.EnumMap` with the keys being template names; it previously used a `std.StaticStringMap`).

Everything else (i.e. core idea - templates, variants, structural matching, etc. and their final implementations/decisions) is my original thought and work.

## License

Licensed under the [MIT License](./LICENSE).

## Cat picture

![a white and slightly brown cat sleeping on a bed, curled up](./assets/PXL_20250605_133823374.jpg)
