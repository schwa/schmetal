# smetal

Proof of concept: a shading language written in Swift syntax (`.smetal`), type-checked by
`swiftc` itself, translated to specialized `.metal` source, and compiled to `.metallib`
with `xcrun metal` / `metallib`.

```
.smetal --swiftc JSON AST--> canonical nodes --emitter--> .metal --metal--> .air --metallib--> .metallib
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
xcb run -- dump Examples/add.smetal              # print the normalized typed AST
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

## Buffer bindings and uniforms

Use `@buffer(slot)` on entry-point parameters to select explicit buffer slots:

```swift
struct Uniforms { var scale: Float; var offset: Float }

@compute
func transform(@buffer(0) input: Buffer<Float>,
               @buffer(3) uniforms: Uniforms,
               @buffer(5) output: Buffer<Float>,
               gid: GridIndex) {
    output[gid] = input[gid] * uniforms.scale + uniforms.offset
}
```

- `Buffer<T>` lowers to a writable `device T*`.
- Annotated scalars and structs lower to read-only `constant T&` arguments.
- Unannotated structs remain `[[stage_in]]`; they do not consume a buffer slot.
- Explicit slots are reserved first. Remaining resources take the lowest unused
  slots in parameter order. With no annotations, existing numbering is unchanged.
- Each entry point allocates its own slots. Duplicates within an entry point are errors.
- Slot arguments must be nonnegative integer literals from 0 through 30.
  Decimal, hexadecimal, octal, and binary spellings are supported; named constants
  and expressions are not evaluated.
- Helpers and built-in index parameters cannot carry `@buffer`.

The annotation is a read-only Swift parameter property wrapper. Device-buffer
elements remain writable through their nonmutating subscript setter.
Host code must bind the specified slots and pack uniform bytes using the emitted
Metal layout. For example, a `Float4` member requires 16-byte alignment.

## Type identity

Compilation uses only `swiftc -frontend -dump-ast -dump-ast-format json`. Each source
gets a primary-file invocation with an explicit SDK. JSON arrives on stdout;
diagnostics arrive on stderr. Failed compiler invocations never reach lowering.

Type fields carry canonical mangled identities. A batched `swift-demangle --expand
--tree-only` adapter decodes nominal types, metatypes, and generic arguments.
Aliases and qualified spellings share an identity; a user-defined `Float` remains
distinct from `Swift.Float`. Unsupported type shapes fail during lowering.

Declaration references use USRs rather than printed names or source-path fragments.
Locals need separate lexical binding because their USRs can be empty. Shadowed locals
get distinct Metal names so their initializers still refer to the outer binding.
Nested shader structs also receive distinct internal Metal names.

JSON omits lvalue type qualifiers; read/write handling uses expression structure.
Source locations use UTF-8 byte offsets, mapped back to the original shader path.

## Layout

- `Sources/smetal/Prelude.swift` — the `SMetal` module source swiftc type-checks against
- `Sources/smetal/TypedAST.swift` — frontend invocation and declaration registry
- `Sources/smetal/JSONASTDecoder.swift` — checked JSON AST normalization and source locations
- `Sources/smetal/DemangledSymbol.swift` — canonical type and declaration-owner decoding
- `Sources/smetal/LocalBindings.swift` — lexical local-reference resolution
- `Sources/smetal/Emitter.swift` — typed AST → MSL
- `Sources/smetal/BufferBindings.swift` — validated explicit and automatic slot allocation
- `Sources/smetal/MetalCompiler.swift` — `.metal` → `.metallib`

No external dependencies; everything needed is in the Xcode toolchain.

## How the attributes work

Stage markers use global actors; member and buffer parameter markers use property wrappers.
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

- Compilation invokes `swiftc` and `swift-demangle`; it is not an in-process frontend.
- Neither JSON AST schemas nor the demangler tree output are guaranteed stable.
  The adapter and regression suite are tested with Apple Swift 6.4.
- Prelude bodies are type-checking stubs, not executable reference implementations.
  Metal mappings remain explicit; the GPU tests cover selected operations, not every mapping.
- Host binding indices and data layout must match the generated Metal interface.
  There is no host-side binding or layout generator.
- Definite-initialization runs in SILGen, which `-dump-ast` stops short of, so
  `var out: VertexOut` with no initializer is accepted (and is what shaders want).
