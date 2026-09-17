import Foundation
import Testing
@testable import smetal

private func withShader(_ source: String, body: (String) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "test.smetal")
    try source.write(to: file, atomically: true, encoding: .utf8)
    try body(file.path)
}

@Test func `buffer vector subscript and scalar multiplication compile`() throws {
    try withShader("""
    import SMetal
    struct VertexOut {
        @position var position: Float4
        var color: Float4
    }
    @vertex
    func vertexMain(id: VertexIndex, positions: Buffer<Float4>, colors: Buffer<Float4>) -> VertexOut {
        var output: VertexOut
        output.position = positions[id]
        output.color = colors[id] * 0.5
        return output
    }
    @fragment
    func fragmentMain(input: VertexOut) -> Float4 { return input.color }
    """) { path in
        let ast = try TypedAST(path: path)
        var emitter = Emitter(ast: ast)
        let metal = try emitter.emit()
        #expect(metal.contains("device float4 *positions"))
        #expect(metal.contains("(colors[id] * 0.5)"))
        let metalPath = path + ".metal"
        let libraryPath = path + ".metallib"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: libraryPath)
        #expect(FileManager.default.fileExists(atPath: libraryPath))
    }
}

@Test func `local types are inferred without annotations`() throws {
    try withShader("""
    import SMetal
    @compute
    func infer(a: Buffer<Float>, out: Buffer<Float>, gid: GridIndex) {
        let doubled = a[gid] * 2.0
        out[gid] = doubled
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("float doubled = (a[gid] * 2.0)"))
    }
}

@Test func `global constant can be specialized`() throws {
    try withShader("""
    import SMetal
    let scale: Float = 2.0
    @compute
    func scaled(out: Buffer<Float>, gid: GridIndex) { out[gid] = scale }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path), specializations: ["scale": "8.0"])
        let metal = try emitter.emit()
        #expect(metal.contains("constant float scale = 8.0;"))
    }
}

@Test func `unknown shader type is rejected`() throws {
    try withShader("import SMetal\nfunc bad(value: MissingType) {}") { path in
        #expect(throws: SMetalError.self) { try TypedAST(path: path) }
    }
}

@Test func `vector buffer cannot be assigned to scalar`() throws {
    try withShader("""
    import SMetal
    func bad(values: Buffer<Float4>) {
        var value: Float = 0.0
        value = values[0]
    }
    """) { path in
        #expect(throws: SMetalError.self) { try TypedAST(path: path) }
    }
}

@Test func `frontend rejects driver failures without source locations`() throws {
    let missing = "/tmp/smetal-missing-\(UUID().uuidString).swift"
    do {
        _ = try SwiftFrontend.dumpAST(files: [missing], shaderName: "missing.swift")
        Issue.record("Frontend accepted a failed compiler invocation")
    } catch let error as SMetalError {
        #expect(error.description.contains(missing))
        #expect(error.description.contains("error:"))
    }
}

@Test func `frontend failure keeps source context even in nonstrict mode`() throws {
    try withShader("import SMetal\nfunc bad(value: MissingType) {}") { path in
        do {
            _ = try TypedAST(path: path, strict: false)
            Issue.record("Accepted a failed type check in nonstrict mode")
        } catch let error as SMetalError {
            #expect(error.description.contains("\(path):2:"))
            #expect(error.description.contains("MissingType"))
            #expect(error.description.contains("func bad(value: MissingType) {}"))
        }
    }
}
