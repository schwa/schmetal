# smetal

Proof of concept: a shading language written in Swift syntax (`.smetal`), type-checked by
`swiftc` itself, translated to specialized `.metal` source, and compiled to `.metallib`
with `xcrun metal` / `metallib`.

```
.smetal --swiftc -dump-ast--> typed AST --emitter--> .metal --xcrun metal--> .air --metallib--> .metallib
```

The shader is compiled as ordinary Swift against a generated prelude, so name resolution,
overload selection, and type inference are the real Swift implementations rather than an
approximation of them.

## Use

```fish
xcb build
xcb run -- build Examples/add.smetal              # → add.metal + add.metallib
xcb run -- build Examples/add.smetal -D scale=8.0 # specialize a global constant
xcb run -- build Examples/add.smetal --emit-metal # stop after .metal
xcb run -- dump  Examples/add.smetal              # print the msf AST
```

## Language subset

```swift
let scale: Float = 2.0            // → constant float scale = 2.0;  (override with -D)

@compute                          // @compute / @vertex / @fragment; no attribute = helper
func addArrays(a: Buffer<Float>,  // → device float *a [[buffer(0)]]
               b: Buffer<Float>,
               out: Buffer<Float>,
               gid: GridIndex) {  // → uint gid [[thread_position_in_grid]]
    let sum = a[gid] * scale + b[gid]  // type inferred
    out[gid] = sum
}
```

Supported: `let`/`var` with or without annotations, assignment, `if`/`else`, `while`,
`return`, literals, binary/unary/ternary/paren expressions, subscripts, member access,
struct declarations and initializers, calls to helper functions in the same file, and a
fixed set of Metal intrinsics (`min`, `max`, `abs`, `sqrt`, `sin`, `cos`, `pow`, `clamp`,
`floor`, `ceil`, `mix`, `dot`, plus scalar/vector conversions).

Math overloads: `sqrt`, `sin`, `cos`, `floor`, `ceil`, `abs`, `pow`, `min`, `max`,
`clamp`, and `mix` accept `Float`, `Double`, `Half`, and `Float2/3/4`. Arguments
have matching types; vector `mix` also accepts a scalar `Float` weight.
`dot` accepts matching `Float2/3/4` arguments and returns `Float`.
`Double` lowers to Metal `float`, not double precision.

Types: `Float`, `Double`, `Int`, `Int32`, `UInt`, `UInt32`, `Bool`, `Half`,
`Float2/3/4`, `UInt2/3`, `Buffer<T>`, `GridIndex`, `VertexIndex`, `InstanceIndex`.

Struct members take `@position`, `@pointSize`, `@flat`, and `@color`, which become the
matching MSL member attributes.

Everything else is a compile error, reported as a `swiftc` diagnostic against the
`.smetal` line that caused it.

## Layout

- `Sources/smetal/Prelude.swift` — the `SMetal` module source swiftc type-checks against
- `Sources/smetal/TypedAST.swift` — runs `swiftc -dump-ast`, parses the dump
- `Sources/smetal/Emitter.swift` — typed AST → MSL
- `Sources/smetal/MetalCompiler.swift` — `.metal` → `.metallib`

No external dependencies; everything needed is in the Xcode toolchain.

## How the attributes work

Swift has no user-definable function attributes, so the prelude borrows two existing
features and never uses them for their real purpose:

- `@compute` / `@vertex` / `@fragment` are **global actors**. `@compute func f()` is legal
  Swift and arrives as `custom_attr type="compute"`. Nothing is ever isolated or awaited.
- `@position` / `@pointSize` / `@flat` / `@color` are **property wrappers**. The wrapper
  leaves `var_decl interface_type` as the unwrapped type, so lowering reads the declared
  type and discards the synthesized accessors and backing `_name` storage.

This avoids needing a macro plugin, at the cost of two slightly surprising declarations.

## Caveats

- Each build shells out to `swiftc` (~0.5s) instead of calling a parser in-process.
- The `-dump-ast` format is not stable across compiler versions. It goes to **stderr**,
  and rejects both `-o` and `-wmo`, so the dump and the diagnostics share one stream.
- Prelude function bodies are stubs that return garbage. They exist only to type-check;
  lowering is still name-based, so no shader *semantics* are verified.
- No real checking of address spaces or binding indices: buffer numbering is assigned in
  declaration order, not validated against a pipeline.
- Definite-initialization runs in SILGen, which `-dump-ast` stops short of, so
  `var out: VertexOut` with no initializer is accepted (and is what shaders want).
