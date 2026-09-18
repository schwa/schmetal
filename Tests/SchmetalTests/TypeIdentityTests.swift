import Foundation
import Testing
@testable import Schmetal

@Test(arguments: [
    "typealias Scalar = Swift.Float\ntypealias Chained = Scalar\ntypealias Storage<T> = Buffer<T>",
    "typealias Scalar = Swift.Float\ntypealias Chained = Swift.Float\ntypealias Storage<T> = SchmetalShader.Buffer<T>"
])
func `aliases and generic aliases compile using canonical types`(aliases: String) throws {
    try withShader("""
    import Schmetal
    \(aliases)
    typealias Index = GridIndex
    @compute func copy(input: Storage<Chained>, output: Buffer<Scalar>, gid: Index) {
        let value: Scalar = input[gid]
        output[gid] = value + Scalar(2)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("device float *input"))
        #expect(metal.contains("float value"))
        #expect(metal.contains("uint gid [[thread_position_in_grid]]"))
        try compileIdentityMetal(metal, path: path)
    }
}

@Test func `user Float remains distinct from Swift Float`() throws {
    try withShader("""
    import Schmetal
    struct Float { var value: Swift.Float }
    @compute func copy(input: Buffer<Float>, output: Buffer<Swift.Float>, gid: GridIndex) {
        let value = input[gid]
        output[gid] = value.value
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("device float *output"))
        #expect(!metal.contains("device float *input"))
        try compileIdentityMetal(metal, path: path)
    }
}

@Test func `nested nominal types and scoped aliases retain identity`() throws {
    try withShader("""
    import Schmetal
    struct First { struct Value { var number: Swift.Float }; typealias Scalar = Swift.Float }
    struct Second { struct Value { var number: Swift.Int32 } }
    typealias FirstBuffer = Buffer<First.Value>
    @compute func copy(input: FirstBuffer, other: Buffer<Second.Value>, output: Buffer<First.Scalar>, gid: GridIndex) {
        typealias Scalar = Swift.Float
        let value: Scalar = input[gid].number
        output[gid] = value + Swift.Float(other[gid].number)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        try compileIdentityMetal(emitter.emit(), path: path)
    }
}

@Test func `local shadowing preserves initializer binding`() throws {
    try withShader("""
    import Schmetal
    @compute func shadow(input: Buffer<Float>, output: Buffer<Float>, gid: GridIndex) {
        let value = input[gid]
        if value > 0 {
            let value = value + 1
            output[gid] = value
        } else { output[gid] = value }
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(!metal.contains("float value = (value + 1)"))
        try compileIdentityMetal(metal, path: path)
    }
}

private func compileIdentityMetal(_ metal: String, path: String) throws {
    let metalPath = path + ".metal"
    try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
    try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
}
