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
        let tree = try SyntaxTree(path: path)
        var emitter = Emitter(tree: tree)
        let metal = try emitter.emit()
        #expect(metal.contains("device float4 *positions"))
        #expect(metal.contains("colors[id] * 0.5"))
        let metalPath = path + ".metal"
        let libraryPath = path + ".metallib"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: libraryPath)
        #expect(FileManager.default.fileExists(atPath: libraryPath))
    }
}

@Test func `unknown shader type is rejected`() throws {
    try withShader("import SMetal\nfunc bad(value: MissingType) {}") { path in
        #expect(throws: SMetalError.self) { try SyntaxTree(path: path) }
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
        #expect(throws: SMetalError.self) { try SyntaxTree(path: path) }
    }
}
