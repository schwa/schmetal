import Foundation
import Testing

@testable import Schmetal

private func withTemporaryShader(_ source: String, body: (String, String) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appending(path: "test.schmetal").path
    try source.write(toFile: path, atomically: true, encoding: .utf8)
    try body(path, directory.path)
}

private let shader = """
import MetalStdlib
let scale: Float = 2.0
@compute func scaleValues(input: Buffer<Float>, output: Buffer<Float>, gid: GridIndex) {
    output[gid] = input[gid] * scale
}
"""

@Test func `compiler writes metal and library beside the shader`() throws {
    try withTemporaryShader(shader) { path, directory in
        let result = try ShaderCompiler().compile(shaderPath: path)
        #expect(result.metalPath == directory + "/Generated/test.metal")
        #expect(result.libraryPath == directory + "/Generated/test.metallib")
        #expect(FileManager.default.fileExists(atPath: result.metalPath))
        #expect(FileManager.default.fileExists(atPath: try #require(result.libraryPath)))
        // The intermediate .air is cleaned up.
        #expect(!FileManager.default.fileExists(atPath: directory + "/Generated/test.air"))
    }
}

@Test func `emit metal only skips the Metal toolchain`() throws {
    try withTemporaryShader(shader) { path, directory in
        let result = try ShaderCompiler(emitMetalOnly: true).compile(shaderPath: path)
        #expect(result.libraryPath == nil)
        #expect(FileManager.default.fileExists(atPath: result.metalPath))
        #expect(!FileManager.default.fileExists(atPath: directory + "/Generated/test.metallib"))
    }
}

@Test func `specializations replace global constants`() throws {
    try withTemporaryShader(shader) { path, _ in
        let metal = try ShaderCompiler(specializations: ["scale": "8.0"]).lower(shaderPath: path)
        #expect(metal.contains("constant float scale = 8.0;"))
    }
}

@Test func `explicit output paths override the generated directory`() throws {
    try withTemporaryShader(shader) { path, directory in
        let library = directory + "/custom/shader.metallib"
        let result = try ShaderCompiler().compile(
            shaderPath: path, outputs: .init(metalPath: directory + "/custom/shader.metal", libraryPath: library)
        )
        #expect(result.libraryPath == library)
        #expect(FileManager.default.fileExists(atPath: library))
    }
}

@Test func `dump text describes declarations`() throws {
    try withTemporaryShader(shader) { path, _ in
        let text = try ShaderCompiler.dumpText(shaderPath: path)
        #expect(text.contains("func_decl"))
        #expect(text.contains("scaleValues"))
    }
}

@Test func `compilation failures surface the shader path`() throws {
    try withTemporaryShader("import MetalStdlib\nfunc bad() -> Float { \"text\" }\n") { path, directory in
        #expect(throws: SchmetalError.self) { try ShaderCompiler().compile(shaderPath: path) }
        #expect(!FileManager.default.fileExists(atPath: directory + "/Generated/test.metal"))
    }
}
