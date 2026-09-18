# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: Shader files import Schmetal rather than Metal

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:language
created: 2026-09-17T00:38:59Z
updated: 2026-09-18T13:25:52Z
closed: 2026-09-18T13:25:52Z
+++

Shader sources use import Schmetal rather than import Metal. The frontend currently strips that import and stages the shader alongside Prelude.swift. Metal names the host framework, whose API differs from shader-side Buffer and GridIndex. The desired shader module naming remains a language-design choice.

- `2026-09-18T13:25:46Z`: Shader files now import MetalStdlib rather than Schmetal, mirroring MSL's metal_stdlib module. The remaining question is whether that module should become real (resolvable by SourceKit) rather than a staged prelude.

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

- `2026-09-18T13:28:06Z`: Related: #30 wants builtin positions to be standard values with attribute markers, which depends on this issue landing SIMD types first.

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
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:language
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T18:18:00Z
closed: 2026-09-17T18:18:00Z
+++

Buffer parameters are numbered sequentially in declaration order. There is no way to pin a parameter to a specific [[buffer(n)]] slot, so host code and shader order must be kept in sync by hand.

- `2026-09-17T15:57:33Z`: Inspected Emitter.emitParameter, Prelude, README, and the GPU harness: bindings are assigned by parameter order, including scalar constant arguments; there is no existing explicit-slot syntax or metadata channel. Punting because implementing this feature requires a shader-language/API decision, not just emitter plumbing. Concrete unblocker: choose where slots are specified (shader-side parameter annotation versus per-entry-point build configuration), define whether unannotated parameters keep positional slots or take the lowest unused slot, and confirm duplicate/out-of-range slots should be errors. No regression test or source change added because there is no agreed input syntax to test.
- `2026-09-17T18:13:48Z`: Implemented in the working copy, awaiting commit: @buffer(slot) parameter wrappers preserve slot arguments in JSON. BufferBindings reserves explicit slots before assigning the lowest unused slots to automatic resources. Slots are per entry point; duplicate slots, out-of-range values, named constants/expressions, helper annotations, built-in index annotations, unknown parameter markers, and resource-count overflow are rejected. Verified Metal itself limits buffer slots to 0...30. Decimal/hex/octal/binary literal forms and slot 30 compile. GPU readback verifies mixed explicit/automatic assignments. The negative-slot regression also exposed dropped JSON negative-literal flags in ordinary expressions; emission now retains the sign and has regression/GPU coverage. xcb build and all 52 tests pass; original examples still compile. No commit yet.
- `2026-09-17T18:18:00Z`: Implemented and verified: explicit @buffer slots, deterministic automatic allocation, and read-only uniform struct bindings. Build and all 52 tests pass, including compute and render GPU checks. Closing with the implementation commit.

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
status: closed
priority: medium
kind: feature
labels: effort:m, area:lowering
created: 2026-09-17T00:41:30Z
updated: 2026-09-17T18:18:00Z
closed: 2026-09-17T18:18:00Z
+++

A struct parameter on an entry point always lowers to [[stage_in]]. A struct of uniforms (e.g. a transform matrix) has no way to be bound as a constant buffer argument.

- `2026-09-17T18:13:48Z`: Implemented in the working copy, awaiting commit: @buffer(slot) on a struct parameter emits a read-only constant Struct& [[buffer(slot)]]. Unannotated structs keep [[stage_in]]. The parameter wrapper has a let wrappedValue, so writes to uniform fields fail Swift checking while Buffer element writes remain valid. Red tests reproduced missing uniform lowering before the change. Metal compilation tests cover compute uniforms and fragment stage_in plus uniforms. GPU tests verify sparse slots 0/3/5, vertex uniforms changing geometry, fragment uniforms changing color, and padded Float4 layout. README documents binding rules and host responsibility for matching Metal layout. xcb build and all 52 tests pass. No commit yet.
- `2026-09-17T18:18:00Z`: Implemented and verified: explicit @buffer slots, deterministic automatic allocation, and read-only uniform struct bindings. Build and all 52 tests pass, including compute and render GPU checks. Closing with the implementation commit.

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

Errors from 'xcrun metal' reference the generated .metal line numbers, not the .schmetal source. Users have to open the generated file to map the error back.

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

'-D name=value' substitutes the raw string into the generated constant. A value that does not parse as the declared type is not reported by schmetal and only fails in metal.

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
status: closed
priority: high
kind: bug
labels: effort:m, area:lowering
created: 2026-09-17T00:46:05Z
updated: 2026-09-17T17:18:31Z
closed: 2026-09-17T17:18:31Z
+++

The emitter now consumes swiftc type strings instead of source tokens, but metalType still matches a fixed spelling table and Buffer prefix. It does not represent canonical type identity; user typealias declarations are unsupported, and equivalent or qualified type spellings have no established lowering. Prelude and emitter mappings can still drift. Related to #17 for mapping ownership and #20 for resolved declaration identity.

\- `2026-09-17T15:16:26Z`: Related: #20 covers declaration identity for calls/operators; #17 covers keeping prelude definitions and Metal mappings aligned.
\- `2026-09-17T15:19:12Z`: Related architecture task #24 explores hiding compiler-dump details behind a semantic boundary; this issue retains the concrete type-identity problem.
\- `2026-09-17T15:25:22Z`: Reproduced with a regression test: typealias Scalar = Swift.Float used in Buffer<Scalar> and an annotated local fails with unsupported top-level declaration: typealias. Restored the temporary failing test after investigation. With Swift 6.4, text AST parameter/local types retain Scalar; the alias underlying type is printed as Float. A standalone JSON dump instead exposes mangled type references ($sSfD for Swift.Float) and declaration USRs. JSON still has no schema stability guarantee. Punting: alias-name substitution alone does not satisfy the canonical-identity scope, and choosing a new identity representation/source crosses into the unselected #24 frontend design. Concrete unblocker: approve JSON type-reference/USR ingestion for identity, or explicitly narrow this ticket to non-generic alias and qualified-spelling support on the current text AST. Repro: import Schmetal; typealias Scalar = Swift.Float; @compute func copy(input: Buffer<Scalar>, output: Buffer<Scalar>, gid: GridIndex) { let value: Scalar = input[gid]; output[gid] = value }. No source changes retained.
\- `2026-09-17T16:27:14Z`: Investigation update (Apple Swift 6.4, swiftlang-6.4.0.34.1): JSON provides canonical type identities and structured declaration references, not merely easier syntax. Verified Scalar = Swift.Float and alias chains canonicalize to $sSfD; Storage<Chained> and Buffer<Scalar> share $s13SchmetalProbe6BufferVySfGD. Text prints both Swift.Float and a user struct Float as Float, whereas JSON distinguishes $sSfD from $s13SchmetalProbe5FloatVD. Nested nominal types and SIMD aliases also retain distinct/canonical identities. Overloaded calls have decl_usr values matching their declarations. Generic references expose structured substitutions; expression type is instantiated, while decl.type_usr can remain generic.

Recommended implementation direction: JSON alone for compilation; text dumps only as an optional debugging output. Do not merge two AST formats. This is justified by identity information, not a stability guarantee. Neither dump schema is guaranteed stable across compiler versions.

Required adapter work: decode canonical mangled type identities for the supported shader subset rather than parsing pretty names; select processed initializer nodes; match nonlocal declarations by USR; handle locals lexically because their decl_usr can be empty; derive reads/writes from load/assignment/inout structure because JSON canonicalization removes lvalue qualifiers. Alias spelling and some TypeRepr syntax are omitted. Advanced local archetypes can be replaced with existential bounds, so unknown/unsupported types must fail explicitly. JSON is not a strict superset of the text dump.

Source ranges are UTF-8 byte offsets; end offsets point at the final token start, not its exclusive end. Preserve source bytes for diagnostic mapping. Unicode probes confirmed this. Original initializer nodes can have empty types even on successful compilation.

Invocation findings: one-file driver invocations emit AST on stdout; multi-file driver invocations emit concatenated AST documents on stderr. Failed invocations can still emit partial ASTs and mix diagnostics into multi-file output. Check exit status before parsing. A tested alternative is swiftc -frontend -dump-ast -dump-ast-format json -sdk <xcrun --show-sdk-path> -module-name SchmetalProbe -primary-file Shader.swift Support.swift: one primary-file JSON document on stdout with diagnostics on stderr. It needs explicit SDK setup and omits the supporting files top-level AST. Valid adjacent JSON documents can be parsed as a sequence; no handwritten S-expression grammar is necessary.

Demangling probes: swift-demangle --expand exposes nominal/generic/optional/tuple/metatype/function structure. Pretty output is insufficient: the generic function type $syxxcluD produced a tree but its pretty result fell back to the mangled string. A tested type adapter is still needed; parser replacement alone does not complete #16.

Acceptance coverage: aliases and chains; generic aliases; qualified types; distinct same-spelling types; nested names; overload identity; generic substitutions; constructors; local shadowing; lvalue contexts; Unicode source mapping; failed compiler invocations; and the existing compiler/Metal/GPU tests. This establishes feasibility for current concrete shader types, not all Swift semantics.

Source evidence, pinned upstream revision e53ecb99609179c7ae55c3e1eb115fc98266c2af (not claimed to be the exact Apple build source): https://github.com/swiftlang/swift/blob/e53ecb99609179c7ae55c3e1eb115fc98266c2af/lib/AST/ASTDumper.cpp#L1795-L1866 documents structured references and type USRs; https://github.com/swiftlang/swift/blob/e53ecb99609179c7ae55c3e1eb115fc98266c2af/lib/AST/USRGeneration.cpp#L38-L44 explicitly calls getCanonicalType()->getRValueType(). ASTDumper.cpp lines 203-299 explain potentially empty USRs and lossy archetype normalization; lines 1040-1087 explain offsets and context IDs; lines 1963-1975 explain omitted type syntax.

Full local report and reproducible probes: /tmp/schmetal-ast-audit/REPORT.md (temporary; essential findings preserved in this comment). Related #18 remains parser/compatibility coverage, not a claim that JSON is stable. No compiler implementation changed during this investigation.

- `2026-09-17T17:15:19Z`: Implemented in the working copy (not committed yet): compilation now uses JSON-only primary-file frontend invocations with explicit SDK setup. Removed SExpressionParser. Canonical type USRs are preserved and decoded through batched swift-demangle trees; declaration references use USR registry entries and decoded owners. Aliases, alias chains, generic aliases, qualified names, nested nominal types, and user Float versus Swift.Float now lower correctly. Prelude scalar names are Swift-qualified to prevent source shadowing. Local bindings use lexical scopes and rename shadows; source ranges preserve UTF-8 offsets and map to the original path. Unsupported type identities and malformed required JSON shapes fail explicitly. Existing operator/helper/constructor/member checks were migrated to identities, not old printed reference strings. Red regressions reproduced alias rejection, nested-type rejection, scalar-name collision, and shadow-initializer capture before the implementation. xcb build and all 42 tests now pass, including an actual GPU test combining aliases, same-spelling nominal types, overloads, and local shadowing. Both example metallibs and CLI dump work. New adapter/test files pass lint. README documents the remaining JSON schema and demangler-output version dependency. Awaiting commit; issue left Open until the fix is committed.
- `2026-09-17T17:18:31Z`: Committed implementation replaces text AST parsing with JSON-only frontend ingestion, canonical type decoding, USR declaration matching, and lexical local binding. Build and all 42 tests pass, including GPU identity/alias/shadowing coverage; both examples compile to metallib.

---

## 17: Metal lowering rules are not declared alongside stdlib types

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:lowering
created: 2026-09-17T00:46:05Z
updated: 2026-09-18T13:02:56Z
closed: 2026-09-18T13:02:56Z
+++

Prelude.swift declares shader types, while Metal spellings, pointer rules, and entry-point attributes live separately in Emitter.swift. Adding or renaming a type requires keeping both definitions aligned, without a consistency check. The previous msf vocabulary limitation is obsolete, but the duplicated lowering metadata remains.

- `2026-09-17T15:16:26Z`: Related: #16 covers canonical type lowering and #20 covers declaration-aware call/operator lowering.
- `2026-09-17T15:19:12Z`: Related design task #25 explores ownership of the full shader-language contract; this issue retains the specific prelude/lowering metadata drift scope.
- `2026-09-17T15:58:05Z`: Reviewed Prelude.source/mathDeclarations, Emitter type/binding tables, ShaderDeclarations provenance checks, and related #25. Punting: #25 explicitly leaves the ownership interface and metadata mechanism unselected; moving dictionaries beside Prelude would not resolve independent definitions or consistency. Concrete unblocker: approve either a declarative shader-language registry that generates Swift declarations and Metal mappings, or declaration-attached metadata consumed by lowering, and specify whether this applies only to types or also intrinsics/stages/member markers. No source changes or tests added; this is a design decision rather than a reproduced runtime bug.

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
status: closed
priority: high
kind: task
labels: effort:l, area:testing
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T15:57:03Z
closed: 2026-09-17T15:57:03Z
+++

The current tests cover vector buffer access, two type errors, local inference, and constant specialization. Advertised constructors, intrinsics, helper calls, loops, boolean operators, ternaries, and member attributes lack systematic regression coverage. Passing the two examples does not establish compatibility across the previous language surface. Expected: representative accepted and rejected cases, with generated Metal compilation where applicable.

- `2026-09-17T15:16:26Z`: Related: #3 provides runtime GPU checks; #18 covers parser-format tests; #23 covers missing advertised math declarations. Keep these scopes separate.
- `2026-09-17T15:19:12Z`: Related design task #26 explores a compilation boundary for testing. The advertised-language regression coverage remains scoped here.
- `2026-09-17T15:57:03Z`: Extended existing shader tests with valid control flow (while, if/else-if/else), Boolean &&/||/!, ternaries, unary +/- and parentheses, scalar/vector constructors, every member marker (position, pointSize, flat, multiple color outputs), and rejected indexing/member/constructor/Boolean/attribute cases. Existing intrinsic, helper-overload, and GPU coverage remains in place. Red runs found unsupported autoclosure_expr and ternary_expr, unary + protocol provenance, and Int constructor provenance; targeted lowering fixes now pass. Boolean autoclosures unwrap only the validated short-circuit RHS shape, preserving Metal &&/|| evaluation. All valid fixtures compile generated Metal; all 24 tests including GPU cases pass, as does xcb build. Changed tests and declaration validator pass SwiftLint. Marker name collision evidence was recorded on #22.

---

## 22: Shader marker attributes introduce unverified actor and wrapper semantics

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:frontend
created: 2026-09-17T15:12:14Z
updated: 2026-09-17T16:12:43Z
closed: 2026-09-17T16:12:43Z
+++

Stage markers are implemented as global actors and member markers as property wrappers. swiftc applies their ordinary Swift semantics during type checking even though the Metal emitter discards their implementation. Cross-stage calls, helper isolation, property initialization, and synthesized memberwise constructors have not been audited. Expected: documented and tested effects on which shader programs are accepted or rejected; do not assume these markers are semantically inert.

- `2026-09-17T15:19:12Z`: Related design task #25 covers shader-language ownership. Actor and wrapper semantic validation remains scoped here.
- `2026-09-17T15:57:03Z`: During #21 coverage work, a fixture declaring functions literally named vertex and fragment failed swiftc with invalid redeclaration of vertex/fragment because the prelude declares global actors with those names. Renaming the fixture functions to vertexMain/fragmentMain allowed all member-attribute compilation tests to pass. Include this verified name collision in the marker-semantics audit.
- `2026-09-17T16:12:43Z`: Completed marker semantics audit with dedicated boundary tests and README table. Verified all six cross-stage directions plus nonisolated callers to all three stages reject synchronous actor-isolated calls; same-stage calls pass Swift checking but fail lowering. Ordinary labeled/unlabeled/nullary helpers work across stages and compile to Metal. Verified all three actor names collide with function declarations; memberwise wrapper constructors take wrapped values, reject wrapper objects, and omit wrapper implementation from MSL. Verified AST acceptance versus SIL definite-initialization rejection for member-by-member local construction. Red audit tests exposed silent loss of default property initialization and unresolved unlabeled helper references: now reject stored-property initializers explicitly and match the compiler reference spelling using declaration provenance/signature/type. Documented current-toolchain limits, not a general Swift compatibility guarantee. xcb build and all 31 tests including GPU checks pass; new tests and declaration validator pass lint.

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
status: closed
priority: medium
kind: task
labels: effort:m, area:language
created: 2026-09-17T15:17:59Z
updated: 2026-09-18T13:02:56Z
closed: 2026-09-18T13:02:56Z
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
status: closed
priority: medium
kind: task
labels: effort:m, area:frontend
created: 2026-09-17T15:17:59Z
updated: 2026-09-18T13:21:31Z
closed: 2026-09-18T13:21:31Z
+++

Architecture RFC candidate: deepen ownership of the compilation lifecycle. CLI, prelude staging, frontend execution, diagnostics, and MetalCompiler divide responsibility for temporary files, subprocess failures, output paths, and cleanup. Tests manually reconstruct the compilation sequence, leaving its integration behavior difficult to exercise independently of the CLI.

Scope: explore one owner for compilation orchestration and artifact lifecycle while keeping argument parsing and presentation in the CLI. No interface has been selected.

Dependencies: local filesystem and external toolchain processes. Simulated process results can exercise failures, but cannot replace real-tool integration checks.

Test impact: replace manual pipeline assembly with compilation-boundary tests covering outputs, diagnostics, failures, and cleanup. Retain real Swift/Metal integration coverage.

Related: #19 tracks subprocess correctness; #21 tracks language regression coverage.

- `2026-09-17T15:19:12Z`: Triage: effort:m sizes the compilation-lifecycle RFC/design exploration. Related to #19 (subprocess correctness) and #21 (regression coverage); fixes to those issues need not wait for this design.

---

## 27: Double type-checks but silently lowers to single precision

+++
status: new
priority: medium
kind: bug
labels: area:language, effort:s
created: 2026-09-18T13:20:34Z
+++

Shaders can declare and use `Double` values: the prelude advertises `Double` math overloads and the lowering tables map `Swift.Double` to Metal `float`.

Metal has no double precision, so a shader written with `Double` runs at single precision with no diagnostic. The source claims a precision the compiled shader does not have.

Repro:
1. Write a shader containing `let value: Double = 1.0`.
2. Build it.
3. The generated Metal declares `float value`.

Expected: `Double` is either rejected with a clear diagnostic, or its demotion is a documented, deliberate contract.
Actual: silent demotion to `float`.

Note: rejecting `Double` makes unannotated float literals (which default to `Double`) fail to type-check; see the companion issue about literal defaulting.

---

## 28: Unannotated float literals infer Double, forcing explicit Float annotations

+++
status: new
priority: medium
kind: enhancement
labels: area:language, effort:m
depends: 27
created: 2026-09-18T13:20:40Z
+++

Every floating-point local in a shader needs an explicit `: Float` annotation, because a bare literal infers Swift's default literal type `Double`.

```swift
var x: Float = 0.0   // required
var x = 0.0          // infers Double
```

Mixing the two is a type error, since shaders have no implicit conversions, so the annotations are load-bearing rather than stylistic. Examples/mandelbrot.schmetal annotates every scalar for this reason.

Unclear whether the prelude can influence literal defaulting for a shader translation unit (the Swift stdlib's `FloatLiteralType` typealias is not generally overridable per module). Needs investigation before any behaviour change.

Expected: a bare float literal in a shader behaves as `Float`, or the constraint is documented and diagnosed clearly.
Actual: it infers `Double`, which today lowers silently to Metal `float` (see #27).

---

## 29: Int and UInt silently narrow to 32-bit Metal integers

+++
status: new
priority: medium
kind: bug
labels: area:language, effort:s
created: 2026-09-18T13:21:22Z
+++

`Swift.Int` and `Swift.UInt` are 64-bit on the host but lower to Metal `int` and `uint`, which are 32-bit. The narrowing has no diagnostic.

Integer literals default to `Int`, so unannotated integer locals take the 64-bit type by default, and `Int` is the natural spelling a Swift author reaches for. Examples/mandelbrot.schmetal uses `Int` for its iteration counter.

Repro:
1. Write a shader containing `let value: Int = 3000000000`.
2. Build it.
3. The generated Metal declares `int value`, which cannot represent the value.

Expected: either `Int`/`UInt` are rejected in favour of `Int32`/`UInt32`, or the width contract is documented and out-of-range values are diagnosed.
Actual: silent narrowing to 32-bit.

There is also no supported spelling for a 64-bit integer: `Int64` and `UInt64` are not in the shader vocabulary at all.

Related: #27 (Double demoted to float) and #28 (literal defaulting) are the same problem in the floating-point domain.

---

## 30: Builtin positions use bespoke index types instead of attribute markers on standard values

+++
status: new
priority: medium
kind: enhancement
labels: area:language, effort:m
depends: 2
created: 2026-09-18T13:28:01Z
+++

`GridIndex`, `VertexIndex`, and `InstanceIndex` are custom types whose only job is to name which Metal entry-point attribute a parameter binds to. The value they carry is an integer, reachable through `.raw`.

Consequences:
- Every additional builtin needs a new type. Metal has many (`threadgroup_position_in_grid`, `thread_position_in_threadgroup`, `thread_index_in_threadgroup`, `threads_per_threadgroup`, and more), none of which are supported.
- The types are scalar, so only 1D dispatch is expressible. There is no way to write a 2D or 3D thread position.
- Arithmetic requires unwrapping through `.raw`, unlike the standard integer types it shadows.

Stage markers (`@compute`) and struct member markers (`@position`, `@flat`) already use property wrappers to attach Metal attributes to ordinary declarations; entry-point builtins do not follow that pattern.

Expected: a builtin position is an ordinary integer or vector value carrying an attribute marker.
Actual: it is a distinct nominal type per builtin, scalar only.

Depends on #2: the value type should be a standard SIMD type rather than another bespoke vector struct.

---

## 31: Multidimensional dispatch is not expressible

+++
status: new
priority: medium
kind: feature
labels: area:language, effort:m
depends: 30
created: 2026-09-18T13:28:06Z
+++

Shaders can only describe 1D compute dispatch. `GridIndex` lowers to a scalar `uint [[thread_position_in_grid]]`, so a kernel cannot receive a 2D or 3D thread position, and `Buffer` subscripts take a single linear index.

Examples/mandelbrot.schmetal works around this by taking a `width` uniform and computing row and column from the linear index by hand.

Expected: a kernel can declare a 2D or 3D thread position and threadgroup geometry.
Actual: only a scalar linear index is available.

---

## 32: Address space is inferred from the parameter type and cannot be stated

+++
status: new
priority: medium
kind: feature
labels: area:language, effort:m
created: 2026-09-18T13:44:03Z
+++

A shader cannot say which Metal address space a parameter uses. The emitter derives it from the Swift type:

- `Buffer<T>` becomes `device T*`, always writable.
- A struct or scalar with `@buffer(n)` becomes `constant T&`, always read-only.

`@buffer(n)` only selects a slot; it carries no address space information.

Consequences:
- A read-only array must still be declared `device`. There is no `constant T*`, which is the usual way to pass vertex data and lookup tables.
- A writable single value cannot be expressed. There is no `device T&`.
- `threadgroup` and `ray_data` are not reachable at all, so threadgroup memory and intersection payloads cannot be written.

Expected: the address space is part of what a parameter declares.
Actual: it is a fixed consequence of the parameter type.

---

## 33: Alternative backend: emit LLVM IR and compile via llvm-to-air

+++
status: new
priority: low
kind: enhancement
labels: effort:xl,area:backend
created: 2026-09-18T14:15:21Z
+++

Idea, not planned. Recorded so it is not rediscovered.

Instead of emitting `.metal` text and shelling out to `xcrun metal`, schmetal could emit LLVM IR (or an MLIR dialect) and lower it to AIR bitcode, then package a `.metallib` directly. That removes the Xcode toolchain dependency from the compile path.

Prior art: <https://github.com/xdslproject/llvm-to-air> (reverse-engineered LLVM IR -> AIR -> metallib lowering, written in Python/xDSL, ~560 lines for the core pass).

Why we are not doing it:

- That project is compute-only. There is no vertex/fragment, stage_in, interpolation, or texture support, so `@vertex`/`@fragment` shaders have no lowering path. The graphics half of AIR metadata is the undocumented, hard part.
- Every MSL stdlib call (`dot`, `clamp`, `pow`, vector constructors, texture sampling) is currently resolved for free by the Metal frontend. Through LLVM IR each one must be hand-lowered to an AIR intrinsic.
- AIR is proprietary and version-sensitive, so the lowering is brittle across OS releases.

If ever revisited, the scoped version is a compute-only second backend behind a flag, with the `.metal` text path kept for graphics.

---
