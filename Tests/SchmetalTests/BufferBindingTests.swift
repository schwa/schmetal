import Foundation
import Testing
@testable import schmetal

@Test func `explicit slots are reserved before automatic bindings`() throws {
    try withShader("""
    import Schmetal
    @compute
    func bindings(automatic: Buffer<Float>, @buffer(0) pinned: Buffer<Float>,
                  @buffer(3) scale: Float, output: Buffer<Float>, gid: GridIndex) {
        output[gid] = automatic[gid] + pinned[gid] * scale
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("device float *automatic [[buffer(1)]]"))
        #expect(metal.contains("device float *pinned [[buffer(0)]]"))
        #expect(metal.contains("constant float &scale [[buffer(3)]]"))
        #expect(metal.contains("device float *output [[buffer(2)]]"))
        try compileBindingMetal(metal, path: path)
    }
}

@Test(arguments: [
    "@compute func bad(@buffer(1) first: Buffer<Float>, @buffer(1) second: Buffer<Float>) {}",
    "@compute func bad(@buffer(-1) values: Buffer<Float>) {}",
    "@compute func bad(@buffer(31) values: Buffer<Float>) {}",
    "let slot = 2\n@compute func bad(@buffer(slot) values: Buffer<Float>) {}",
    "func helper(@buffer(2) values: Buffer<Float>) {}",
    "@compute func bad(@buffer(2) gid: GridIndex) {}",
    "@compute func bad(@position values: Buffer<Float>) {}",
    "@compute func bad(@buffer(0x1e) first: Float, @buffer(30) second: Float) {}"
])
func `invalid explicit buffer bindings are rejected`(source: String) throws {
    try withShader("import Schmetal\n" + source) { path in
        let ast = try TypedAST(path: path)
        #expect(throws: SchmetalError.self) {
            var emitter = Emitter(ast: ast)
            _ = try emitter.emit()
        }
    }
}

@Test(arguments: ["30", "0x1e", "0o36", "0b11110", "3_0"])
func `highest supported explicit buffer slot compiles`(literal: String) throws {
    try withShader("""
    import Schmetal
    @compute func lastSlot(@buffer(\(literal)) output: Buffer<Float>, gid: GridIndex) { output[gid] = 1 }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("[[buffer(30)]]"))
        try compileBindingMetal(metal, path: path)
    }
}

@Test func `annotated structs become constant buffers`() throws {
    try withShader("""
    import Schmetal
    struct Uniforms { var scale: Float; var offset: Float }
    @compute func transform(input: Buffer<Float>, @buffer(3) uniforms: Uniforms,
                            output: Buffer<Float>, gid: GridIndex) {
        output[gid] = input[gid] * uniforms.scale + uniforms.offset
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        let parameter = try #require(metal.split(separator: "\n").first { $0.contains("&uniforms") })
        #expect(parameter.contains("constant "))
        #expect(parameter.contains("[[buffer(3)]]"))
        #expect(metal.contains("device float *input [[buffer(0)]]"))
        #expect(metal.contains("device float *output [[buffer(1)]]"))
        #expect(!metal.contains("[[stage_in]]"))
        try compileBindingMetal(metal, path: path)
    }
}

@Test func `stage inputs and uniform structs remain distinct`() throws {
    try withShader("""
    import Schmetal
    struct Varying { @position var position: Float4; var color: Float4 }
    struct Uniforms { var scale: Float }
    @fragment func fragmentMain(input: Varying, @buffer(2) uniforms: Uniforms) -> Float4 {
        return input.color * uniforms.scale
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("input [[stage_in]]"))
        #expect(metal.contains("&uniforms [[buffer(2)]]"))
        try compileBindingMetal(metal, path: path)
    }
}

@Test func `uniform wrappers are readonly but device buffers remain writable`() throws {
    try withShader("""
    import Schmetal
    struct Uniforms { var scale: Float }
    @compute func bad(@buffer(3) uniforms: Uniforms) { uniforms.scale = 2 }
    """) { path in
        #expect(throws: SchmetalError.self) { try TypedAST(path: path) }
    }
}

@Test func `signed JSON literals retain their sign in emitted expressions`() throws {
    try withShader("""
    import Schmetal
    @compute func negative(output: Buffer<Float>, gid: GridIndex) {
        let value: Float = -2
        output[gid] = value + -1.5
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("= -2;"))
        #expect(metal.contains("+ -1.5"))
        try compileBindingMetal(metal, path: path)
    }
}

@Test func `automatic bindings reject resource count overflow`() throws {
    let parameters = (0..<32).map { "value\($0): Buffer<Float>" }.joined(separator: ", ")
    try withShader("import Schmetal\n@compute func tooMany(\(parameters)) {}") { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        do {
            _ = try emitter.emit()
            Issue.record("Accepted too many resource bindings")
        } catch let error as SchmetalError {
            #expect(error.description.contains("more than 31 buffer bindings"))
        }
    }
}

func compileBindingMetal(_ metal: String, path: String) throws {
    let metalPath = path + ".metal"
    try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
    try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
}
