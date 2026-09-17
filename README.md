# smetal

Proof of concept: a shading language written in Swift syntax (`.smetal`), parsed with
[msf](file:///Users/schwa/Projects/Vendor/msf) (Mini Swift Frontend), translated to
specialized `.metal` source, and compiled to `.metallib` with `xcrun metal` / `metallib`.

```
.smetal --msf--> Swift AST --emitter--> .metal --xcrun metal--> .air --metallib--> .metallib
```

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
    let sum: Float = a[gid] * scale + b[gid]
    out[gid] = sum
}
```

Supported: typed `let`/`var`, assignment, `if`/`else`, `while`, `return`, literals,
binary/unary/ternary/paren expressions, subscripts, member access, and a fixed set of
Metal intrinsics (`min`, `max`, `abs`, `sqrt`, `sin`, `cos`, `pow`, `clamp`, `floor`,
`ceil`, `mix`, `dot`, plus `Float`/`Int`/`UInt` casts).

Types: `Float`, `Double`, `Int`, `Int32`, `UInt`, `UInt32`, `Bool`, `Half`,
`Float2/3/4`, `UInt2/3`, `Buffer<T>`, `GridIndex`.

Everything else is a compile error. Type annotations are required — no inference.

## Layout

- `Sources/CMSF` — modulemap over `msf.h`
- `Sources/MSFStubs` — `module_stub_find` stub the static lib needs
- `Sources/smetal/SyntaxTree.swift` — Swift wrapper over the msf AST
- `Sources/smetal/Emitter.swift` — AST → MSL
- `Sources/smetal/MetalCompiler.swift` — `.metal` → `.metallib`

## Caveats

- Paths to msf (`~/Projects/Vendor/msf`) are hardcoded in `Package.swift` and the modulemap.
  Run `make release` in msf first.
- msf reports unresolved-symbol errors for shader types (`Buffer`, `GridIndex`); they are
  downgraded to a note. A real implementation would feed msf a `.msfvocab` of the shader
  standard library instead.
- No real type checking of shader semantics: address spaces, bindings, and intrinsics are
  pattern-matched, not verified.
