import Foundation
import Testing
@testable import Schmetal

@Test(arguments: ["compute", "vertex", "fragment"])
func `stage actor names collide with function declarations`(name: String) throws {
    try withShader("import MetalStdlib\nfunc \(name)() {}") { path in
        do {
            _ = try TypedAST(path: path)
            Issue.record("Expected marker name collision")
        } catch let error as SchmetalError {
            #expect(error.description.contains("invalid redeclaration"))
        }
    }
}

@Test(arguments: [
    ("compute", "@vertex"), ("compute", "@fragment"), ("compute", ""),
    ("vertex", "@compute"), ("vertex", "@fragment"), ("vertex", ""),
    ("fragment", "@compute"), ("fragment", "@vertex"), ("fragment", "")
])
func `cross isolation calls are rejected`(calleeStage: String, callerStage: String) throws {
    try withShader("""
    import MetalStdlib
    @\(calleeStage) func isolatedValue() -> Float { 1 }
    \(callerStage) func caller() -> Float { isolatedValue() }
    """) { path in
        do {
            _ = try TypedAST(path: path)
            Issue.record("Expected isolation diagnostic")
        } catch let error as SchmetalError {
            #expect(error.description.contains("actor-isolated"))
        }
    }
}

@Test func `same stage calls type check but entry point calls cannot lower`() throws {
    try withShader("""
    import MetalStdlib
    @compute func isolatedValue() -> Float { 1 }
    @compute func caller(output: Buffer<Float>, gid: GridIndex) { output[gid] = isolatedValue() }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        do {
            _ = try emitter.emit()
            Issue.record("Expected entry point call rejection")
        } catch let error as SchmetalError {
            #expect(error.description.contains("only direct calls to supported declarations are allowed"))
        }
    }
}

@Test func `nonisolated helpers work from every stage`() throws {
    try withShader("""
    import MetalStdlib
    struct VertexResult { @position var position: Float4 }
    func helper(_ value: Float) -> Float { value + bias() }
    func bias() -> Float { 1 }
    @compute func kernelMain(output: Buffer<Float>, gid: GridIndex) { output[gid] = helper(1) }
    @vertex func vertexMain() -> VertexResult {
        return VertexResult(position: Float4(helper(1), 0, 0, 1))
    }
    @fragment func fragmentMain() -> Float4 { return Float4(helper(1), 0, 0, 1) }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(!metal.contains("wrappedValue"))
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test func `wrapper memberwise constructors accept wrapped values and reject wrapper objects`() throws {
    try withShader("""
    import MetalStdlib
    struct VertexResult { @position var position: Float4 }
    func bad(value: Float4) -> VertexResult { VertexResult(position: position(wrappedValue: value)) }
    """) { path in
        do {
            _ = try TypedAST(path: path)
            Issue.record("Expected wrapper argument type rejection")
        } catch let error as SchmetalError {
            #expect(error.description.contains("cannot convert value"))
        }
    }
}

@Test func `default wrapped property initialization type checks but cannot lower`() throws {
    try withShader("""
    import MetalStdlib
    struct VertexResult { @position var position: Float4 = Float4(0, 0, 0, 1) }
    @vertex func vertexMain() -> VertexResult { VertexResult() }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        do {
            _ = try emitter.emit()
            Issue.record("Expected default argument rejection")
        } catch let error as SchmetalError {
            #expect(error.description.contains("stored property initializers are unsupported"))
        }
    }
}

@Test func `member by member wrapper initialization passes AST checking but not SIL initialization checks`() throws {
    try withShader("""
    import MetalStdlib
    struct VertexResult { @position var position: Float4; var tint: Float4 }
    @vertex func vertexMain() -> VertexResult {
        var result: VertexResult
        result.position = Float4(0, 0, 0, 1)
        result.tint = Float4(1, 0, 0, 1)
        return result
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("result.position ="))
        let staged = try Prelude.stage(shaderPath: path)
        defer { try? FileManager.default.removeItem(at: staged.directory) }
        do {
            _ = try ToolProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["swiftc", "-emit-sil", "-wmo", "-module-name", "SchmetalShader",
                            staged.prelude.path, staged.shader.path,
                            "-o", staged.directory.appending(path: "test.sil").path]
            )
            Issue.record("Expected definite initialization diagnostic")
        } catch let error as SchmetalError {
            #expect(error.description.contains("before being initialized"))
        }
    }
}
