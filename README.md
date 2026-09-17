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

## Tests

Run `xcb test`. GPU integration tests compile the example shaders, load their
libraries, and check compute-buffer results and offscreen rendered pixels.
They require a Metal device and the Xcode Metal compiler; missing hardware fails
explicitly. Tests use temporary files and do not modify example artifacts.

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

Globals must be stored constants. Struct methods, computed/static/observed properties,
custom operators, async/throwing functions, indirect calls, and additional imports
are rejected during lowering. Helper overloads receive distinct internal Metal names.

Swift type errors retain source diagnostics. Valid Swift outside the supported shader
subset receives a lowering error rather than being silently ignored.

## Layout

- `Sources/smetal/Prelude.swift` — the `SMetal` module source swiftc type-checks against
- `Sources/smetal/TypedAST.swift` — runs `swiftc -dump-ast`, parses the dump
- `Sources/smetal/Emitter.swift` — typed AST → MSL
- `Sources/smetal/MetalCompiler.swift` — `.metal` → `.metallib`

No external dependencies; everything needed is in the Xcode toolchain.

## How the attributes work

Stage markers use global actors; member markers use property wrappers.
This avoids a macro plugin, but Swift applies the actors' and wrappers' semantics
during type checking. Metal output contains neither actor isolation nor wrapper storage.

The audit tests verify these boundaries with the selected Swift toolchain:

| Source construct | Swift AST checking | Metal lowering |
|---|---|---|
| Synchronous cross-stage call | Rejected by actor isolation | Not reached |
| Nonisolated helper calls a stage function | Rejected by actor isolation | Not reached |
| Same-stage call to another entry point | Accepted | Rejected |
| Stage function calls a nonisolated helper | Accepted | Supported |
| Function named `compute`, `vertex`, or `fragment` | Name collision | Not reached |
| Memberwise constructor given a wrapped value | Accepted | Supported |
| Memberwise constructor given a wrapper object | Type mismatch | Not reached |
| Stored property with a default initializer | Accepted | Rejected; initialization is not implemented |
| Uninitialized struct followed by member assignments | Accepted at AST stage | Supported; ordinary Swift SIL initialization checks reject the tested case |

For example, `VertexResult(position: value)` takes a `Float4`, not a
`position<Float4>` wrapper. Emission keeps the `[[position]]` member attribute
and discards synthesized accessors and backing storage.

These tests characterize the current toolchain and frontend invocation; they do not
guarantee compatibility with other compiler versions or concurrency settings.

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
