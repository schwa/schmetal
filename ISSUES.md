# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: Shader files import SMetal rather than Metal

+++
status: open
priority: low
kind: enhancement
labels: effort:s, area:language
created: 2026-09-17T00:38:59Z
updated: 2026-09-17T15:16:14Z
+++

Shader sources use import SMetal rather than import Metal. The frontend currently strips that import and stages the shader alongside Prelude.swift. Metal names the host framework, whose API differs from shader-side Buffer and GridIndex. The desired shader module naming remains a language-design choice.

---

## 2: Vector types use Float4 instead of SIMD4<Float>

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:language
created: 2026-09-17T00:38:59Z
updated: 2026-09-17T15:16:14Z
+++

Shader vectors use Float2/Float3/Float4/UInt2/UInt3 rather than standard Swift SIMD types such as SIMD4<Float>. The prelude declares custom vector structs and the emitter recognizes their names, but generic SIMD types are not supported end to end.

---

## 3: No end-to-end harness runs compiled shaders on the GPU

+++
status: closed
priority: high
kind: feature
labels: effort:l, area:testing
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:51:41Z
closed: 2026-09-17T15:51:41Z
+++

Tests only check emitted text and that metallib files exist. Nothing loads the metallib with MTLDevice, dispatches a kernel or draws with the vertex/fragment pair, and checks results, so a shader that compiles but computes the wrong values is not caught.

- `2026-09-17T15:16:26Z`: Related to #21: this issue checks GPU results; #21 checks frontend acceptance, emission, and Metal compilation.
- `2026-09-17T15:51:41Z`: Added a Metal GPU integration harness compiling real example sources in temporary directories. Compute tests dispatch addArrays and clampArray over 257 elements, check every result, and cover default scale 2 and specialization 8. Offscreen rendering runs triangleVertex/triangleFragment and checks red interior plus blue cleared exterior pixels. Command completion/errors are checked; missing Metal hardware fails explicitly. Test-only change: no production behavior changed. Validated the oracle by temporarily replacing addition with subtraction in staged source: GPU assertions failed (840 issues), then passed after removing the mutation. xcb build, all 20 tests, and new-file lint pass on this machine. README records hardware/toolchain requirements.

---

## 4: Locals require explicit type annotations

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:frontend
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
closed: 2026-09-17T15:16:14Z
+++

A local declared as 'let sum = a[gid] * scale' fails with 'needs an explicit type annotation' even though msf already resolves the expression type. Normal Swift infers this.

- `2026-09-17T15:16:14Z`: Resolved by ec16549a: Emitter reads inferred pattern types from the typed AST. The local types are inferred without annotations regression test covers this case.

---

## 5: Helper calls lack validated declaration-aware lowering

+++
status: closed
priority: medium
kind: bug
labels: effort:m, area:lowering
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
closed: 2026-09-17T15:16:14Z
+++

The old intrinsic-only rejection was removed in ec16549a, but helpers are now forwarded using declBaseName without validation. Swift declaration references may include argument labels while emitted function declarations use a bare name. Supported helpers need correct call spelling and unsupported callees need rejection. Remaining call-lowering scope is tracked by #20.

- `2026-09-17T15:16:14Z`: Superseded by #20 after the frontend migration: the old allowlist rejection no longer exists; remaining helper-call correctness belongs to declaration-aware call lowering.

---

## 6: Buffer index type is not checked

+++
status: closed
priority: medium
kind: bug
labels: effort:s, area:frontend
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
closed: 2026-09-17T15:16:14Z
+++

Buffer subscripts accept any expression as the index. The stdlib declares subscript(index: UInt32) but msf does not check the argument, so 'buffer[1.5]' or 'buffer[someFloat4]' reaches metal and fails there with an unrelated diagnostic.

- `2026-09-17T15:16:14Z`: Resolved by ec16549a: swiftc resolves Buffer subscripts against the concrete Int, UInt32, GridIndex, VertexIndex, and InstanceIndex overloads in Prelude.source. Arbitrary Float and Float4 indices no longer bypass type checking. Regression coverage remains tracked by #21.

---

## 7: No control over buffer binding indices

+++
status: open
priority: medium
kind: enhancement
labels: effort:m, area:language
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

Buffer parameters are numbered sequentially in declaration order. There is no way to pin a parameter to a specific [[buffer(n)]] slot, so host code and shader order must be kept in sync by hand.

---

## 8: Textures and samplers are not supported

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:language
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

There is no texture or sampler type. Fragment shaders that sample an image cannot be expressed.

---

## 9: Uniform structs cannot be passed as constant buffers

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:lowering
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

A struct parameter on an entry point always lowers to [[stage_in]]. A struct of uniforms (e.g. a transform matrix) has no way to be bound as a constant buffer argument.

---

## 10: for-in loops and ranges are not supported

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:lowering
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

'for i in 0..<count' is rejected. Only while loops are lowered.

---

## 11: Vector swizzles are unsupported

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:language
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

The typed frontend now validates declared vector members, so an unknown member such as Float4.q no longer passes through to Metal. Multi-component swizzles such as Float4.xy are not declared in the prelude and cannot be expressed. Remaining scope: supported swizzle reads and writes, with type checking and Metal lowering.

---

## 12: Metal compiler diagnostics point at generated code

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:diagnostics
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

Errors from 'xcrun metal' reference the generated .metal line numbers, not the .smetal source. Users have to open the generated file to map the error back.

---

## 13: Paths to msf are hard-coded

+++
status: closed
priority: low
kind: task
labels: effort:xs, area:build
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
closed: 2026-09-17T15:16:14Z
+++

Package.swift and the CMSF modulemap contain absolute paths under ~/Projects/Vendor/msf. The package does not build on another machine or checkout location.

- `2026-09-17T15:16:14Z`: Resolved by ec16549a: CMSF and MSFStubs were removed and Package.swift no longer links msf or contains the vendor path.

---

## 14: Global constant specialization is untyped

+++
status: open
priority: low
kind: bug
labels: effort:m, area:lowering
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

'-D name=value' substitutes the raw string into the generated constant. A value that does not parse as the declared type is not reported by smetal and only fails in metal.

---

## 15: Half and matrix types are not usable

+++
status: open
priority: low
kind: feature
labels: effort:l, area:language
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T15:16:14Z
+++

Matrix types and their operations are absent, so matrix transforms cannot be expressed. Half is now an alias for Float16 rather than an empty stub, but half literal, conversion, arithmetic, and Metal emission coverage has not been established. The old claim that Half has no Swift literals is obsolete; remaining scope is end-to-end half coverage plus matrix support.

---

## 16: Type lowering still depends on printed type names

+++
status: open
priority: high
kind: bug
labels: effort:m, area:lowering
created: 2026-09-17T00:46:05Z
updated: 2026-09-17T15:16:14Z
+++

The emitter now consumes swiftc type strings instead of source tokens, but metalType still matches a fixed spelling table and Buffer prefix. It does not represent canonical type identity; user typealias declarations are unsupported, and equivalent or qualified type spellings have no established lowering. Prelude and emitter mappings can still drift. Related to #17 for mapping ownership and #20 for resolved declaration identity.

- `2026-09-17T15:16:26Z`: Related: #20 covers declaration identity for calls/operators; #17 covers keeping prelude definitions and Metal mappings aligned.
- `2026-09-17T15:19:12Z`: Related architecture task #24 explores hiding compiler-dump details behind a semantic boundary; this issue retains the concrete type-identity problem.
- `2026-09-17T15:25:22Z`: Reproduced with a regression test: typealias Scalar = Swift.Float used in Buffer<Scalar> and an annotated local fails with unsupported top-level declaration: typealias. Restored the temporary failing test after investigation. With Swift 6.4, text AST parameter/local types retain Scalar; the alias underlying type is printed as Float. A standalone JSON dump instead exposes mangled type references ($sSfD for Swift.Float) and declaration USRs. JSON still has no schema stability guarantee. Punting: alias-name substitution alone does not satisfy the canonical-identity scope, and choosing a new identity representation/source crosses into the unselected #24 frontend design. Concrete unblocker: approve JSON type-reference/USR ingestion for identity, or explicitly narrow this ticket to non-generic alias and qualified-spelling support on the current text AST. Repro: import SMetal; typealias Scalar = Swift.Float; @compute func copy(input: Buffer<Scalar>, output: Buffer<Scalar>, gid: GridIndex) { let value: Scalar = input[gid]; output[gid] = value }. No source changes retained.

---

## 17: Metal lowering rules are not declared alongside stdlib types

+++
status: open
priority: medium
kind: enhancement
labels: effort:m, area:lowering
created: 2026-09-17T00:46:05Z
updated: 2026-09-17T15:16:14Z
+++

Prelude.swift declares shader types, while Metal spellings, pointer rules, and entry-point attributes live separately in Emitter.swift. Adding or renaming a type requires keeping both definitions aligned, without a consistency check. The previous msf vocabulary limitation is obsolete, but the duplicated lowering metadata remains.

- `2026-09-17T15:16:26Z`: Related: #16 covers canonical type lowering and #20 covers declaration-aware call/operator lowering.
- `2026-09-17T15:19:12Z`: Related design task #25 explores ownership of the full shader-language contract; this issue retains the specific prelude/lowering metadata drift scope.

---

## 18: AST parser edge cases and compiler compatibility lack coverage

+++
status: open
priority: low
kind: task
labels: effort:m, area:frontend
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T15:16:14Z
+++

The handwritten swiftc text-dump parser lacks focused coverage for quoting, escaping, labelled children, parenthesized fields, and compiler-format variation. The text and JSON AST schemas both lack a known compatibility guarantee. Expected: parsing correctness and clear failure for unsupported dump shapes. Per triage decision, JSON is an optional implementation choice, not a required migration or a stability guarantee.

- `2026-09-17T15:16:26Z`: Related to #21: parser fixtures and malformed dump handling here complement language feature regression tests there. JSON remains optional per user decision.
- `2026-09-17T15:19:12Z`: Related architecture task #24 explores the frontend/lowering boundary independently of text versus JSON parsing.

---

## 19: Frontend failures and subprocess output are not handled safely

+++
status: closed
priority: high
kind: bug
labels: effort:m, area:frontend
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T15:29:42Z
closed: 2026-09-17T15:29:42Z
+++

SwiftFrontend.run ignores the swiftc exit status and reads stderr and stdout sequentially. Failures without a recognized file:line:column diagnostic can lose their cause or leave partial AST data available for lowering. Sequential pipe draining can deadlock if stdout fills while stderr is being read; this risk has not been reproduced. Expected: failed frontend invocations cannot produce successful shader output, diagnostics retain their context, and both streams can drain safely.

- `2026-09-17T15:19:12Z`: Related design task #26 explores compilation lifecycle ownership. Subprocess failure handling remains an independent fix here.
- `2026-09-17T15:29:42Z`: Fixed frontend subprocess handling: stdout/stderr captured separately in temporary files, nonzero exits and signals rejected before AST parsing, full failure output retained with shader path remapping. Regression test failed before the fix because dumpAST accepted a missing input file; now passes. Added large dual-stream output, signal, launch failure, status/output preservation, and nonstrict diagnostic-context tests. xcb build and full xcb test pass; new process files pass SwiftLint.

---

## 20: Lowering ignores declaration identity and silently accepts unsupported constructs

+++
status: closed
priority: high
kind: bug
labels: effort:l, area:lowering
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T15:48:18Z
closed: 2026-09-17T15:48:18Z
+++

Emitter dispatches operators and intrinsics by short declaration names, and emitCall forwards unrecognized calls without checking that they refer to supported helpers. Struct emission ignores non-property members and some top-level nodes are skipped. Unsupported Swift semantics can therefore be silently discarded or emitted with unrelated Metal semantics. Expected: resolved declarations determine supported lowering, and unsupported constructs receive explicit errors. Related to #16 and #17, but covers calls and construct validation beyond type spelling.

- `2026-09-17T15:16:26Z`: Supersedes #5: its old intrinsic-only rejection disappeared, while helper-call spelling and validation remain part of this issue. Related to #16 (type identity) and #17 (lowering metadata).
- `2026-09-17T15:19:12Z`: Related architecture task #24 explores a semantic boundary; this issue retains concrete unsupported-construct and declaration-identity correctness work.
- `2026-09-17T15:48:18Z`: Added declaration validation using source provenance, full declaration references, and helper signatures. Known prelude/Swift declarations are required for intrinsic/operator/constructor/member/subscript lowering; arbitrary calls are rejected. Helper overloads get distinct Metal names and prototypes, including calls before definitions. Unsupported imports, mutable globals, struct methods, static/computed/observed properties, async/throwing functions, custom operators, and unsupported bindings now fail explicitly. Removed the generic labelled-node fallback; Boolean condition containers are handled explicitly without dropping clauses. Red tests initially exposed four silently accepted constructs; an additional async case and helper-forward-call case were reproduced and fixed. All 18 tests pass, both examples compile to metallib, and xcb build passes. New validator and test file pass lint; existing emitter/parser complexity lint debt remains. Canonical type identity remains separately tracked by #16.

---

## 21: Typed AST migration lacks regression coverage for advertised language features

+++
status: open
priority: high
kind: task
labels: effort:l, area:testing
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T15:16:14Z
+++

The current tests cover vector buffer access, two type errors, local inference, and constant specialization. Advertised constructors, intrinsics, helper calls, loops, boolean operators, ternaries, and member attributes lack systematic regression coverage. Passing the two examples does not establish compatibility across the previous language surface. Expected: representative accepted and rejected cases, with generated Metal compilation where applicable.

- `2026-09-17T15:16:26Z`: Related: #3 provides runtime GPU checks; #18 covers parser-format tests; #23 covers missing advertised math declarations. Keep these scopes separate.
- `2026-09-17T15:19:12Z`: Related design task #26 explores a compilation boundary for testing. The advertised-language regression coverage remains scoped here.

---

## 22: Shader marker attributes introduce unverified actor and wrapper semantics

+++
status: open
priority: medium
kind: task
labels: effort:m, area:frontend
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T15:16:14Z
+++

Stage markers are implemented as global actors and member markers as property wrappers. swiftc applies their ordinary Swift semantics during type checking even though the Metal emitter discards their implementation. Cross-stage calls, helper isolation, property initialization, and synthesized memberwise constructors have not been audited. Expected: documented and tested effects on which shader programs are accepted or rejected; do not assume these markers are semantically inert.

- `2026-09-17T15:19:12Z`: Related design task #25 covers shader-language ownership. Actor and wrapper semantic validation remains scoped here.

---

## 23: Advertised math intrinsics are missing from the Swift prelude

+++
status: closed
priority: high
kind: bug
labels: effort:m, area:language
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T15:33:17Z
closed: 2026-09-17T15:33:17Z
+++

The README and emitter advertise sqrt, sin, cos, pow, floor, and ceil, but Prelude.source neither declares them nor imports a module providing them to shader files. Such calls cannot reach lowering when swiftc cannot resolve them. Vector and scalar overload coverage is also unverified. Expected: every advertised intrinsic resolves for its documented argument types and emits compilable Metal. Distinct from #5, which concerns extending the fixed intrinsic set.

- `2026-09-17T15:16:26Z`: Related to #21 for regression coverage of advertised intrinsic overloads. The historical #5 allowlist issue is superseded by #20 and is not the missing-prelude-declaration bug.
- `2026-09-17T15:19:12Z`: Related design task #25 covers language-definition ownership; restoring advertised intrinsic support remains a separate correctness issue here.
- `2026-09-17T15:33:17Z`: Added concrete prelude overloads for sqrt/sin/cos/floor/ceil/abs/pow/min/max/clamp/mix across Float, Double, Half, and Float2/3/4, plus vector dot and scalar/vector mix weights. Documented the supported overload surface and existing Double-to-float lowering. Parameterized regression failed before the fix with missing math names and overload errors; all six scalar/vector compilation cases, three dot/vector-mix cases, and four invalid-argument cases now pass. Each valid case compiles generated MSL to metallib. xcb build and full test suite pass. Lint has only the pre-existing large staging tuple warning.

---

## 24: Compiler dump details leak into Metal lowering

+++
status: open
priority: medium
kind: task
labels: effort:m, area:lowering
created: 2026-09-17T15:17:59Z
updated: 2026-09-17T15:19:12Z
+++

Architecture RFC candidate: deepen the boundary between TypedAST and Emitter. The emitter interprets processed_init labels, implicit wrappers, argument-list nesting, and printed declaration references directly. A parsed dump does not establish that its contents have supported shader semantics, so compiler-format changes and unsupported constructs reach code generation.

Scope: explore ownership of dump interpretation, semantic validation, and Metal emission. No interface has been selected. Parser format is independent of this boundary.

Dependencies: in-process transformations with swiftc as an external toolchain dependency.

Test impact: move inference and rejection assertions to the semantic frontend boundary; test Metal emission without compiler-dump-shaped fixtures. Retain real-swiftc integration checks and replace redundant tests rather than layering duplicates.

Related: #16, #18, #20.

- `2026-09-17T15:19:12Z`: Triage: effort:m sizes the RFC/design exploration, not an implementation of an unselected interface. Related to #16 (type identity), #18 (parser coverage), and #20 (semantic validation); those concrete issues remain separate.

---

## 25: Shader language support is split between prelude and lowering tables

+++
status: open
priority: medium
kind: task
labels: effort:m, area:language
created: 2026-09-17T15:17:59Z
updated: 2026-09-17T15:19:12Z
+++

Architecture RFC candidate: deepen ownership of shader-language definitions. Prelude.swift declares Swift types and operations while Emitter.swift separately defines Metal types, intrinsics, stages, and member attributes. Determining whether an operation is supported requires checking both; missing math declarations demonstrate the integration risk.

Scope: explore a single owner for the supported shader-language contract and its Swift/Metal correspondence. No interface or metadata mechanism has been selected.

Dependencies: in-process definitions validated against external Swift and Metal compilers.

Test impact: consolidate scattered feature assertions into boundary tests proving advertised operations both type-check and compile as Metal. Keep tests independent of internal table organization.

Related: #17 describes the existing metadata drift; #22 covers marker semantics; #23 covers missing declarations. This candidate is the broader ownership/design discussion, not a second implementation ticket for those bugs.

- `2026-09-17T15:19:12Z`: Triage: effort:m sizes the ownership/interface design exploration. Related to #17 (mapping drift), #22 (marker semantics), and #23 (missing declarations). This is a design task, not a duplicate implementation ticket for those issues.

---

## 26: Compilation lifecycle has no boundary outside CLI orchestration

+++
status: open
priority: medium
kind: task
labels: effort:m, area:frontend
created: 2026-09-17T15:17:59Z
updated: 2026-09-17T15:19:12Z
+++

Architecture RFC candidate: deepen ownership of the compilation lifecycle. CLI, prelude staging, frontend execution, diagnostics, and MetalCompiler divide responsibility for temporary files, subprocess failures, output paths, and cleanup. Tests manually reconstruct the compilation sequence, leaving its integration behavior difficult to exercise independently of the CLI.

Scope: explore one owner for compilation orchestration and artifact lifecycle while keeping argument parsing and presentation in the CLI. No interface has been selected.

Dependencies: local filesystem and external toolchain processes. Simulated process results can exercise failures, but cannot replace real-tool integration checks.

Test impact: replace manual pipeline assembly with compilation-boundary tests covering outputs, diagnostics, failures, and cleanup. Retain real Swift/Metal integration coverage.

Related: #19 tracks subprocess correctness; #21 tracks language regression coverage.

- `2026-09-17T15:19:12Z`: Triage: effort:m sizes the compilation-lifecycle RFC/design exploration. Related to #19 (subprocess correctness) and #21 (regression coverage); fixes to those issues need not wait for this design.

---
