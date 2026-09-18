import Foundation
import Testing

@testable import Schmetal

/// The boundary contract: everything `ShaderLanguage` advertises must both
/// type-check as Swift and compile as Metal.
struct AdvertisedCall {
    let type: String
    let resultType: String
    let expression: String
}

private func advertisedIntrinsicCalls() -> [AdvertisedCall] {
    let vectors = ShaderLanguage.vectorTypes.filter(\.arithmetic)
    let types = [("Float", "Float")] + vectors.map { ($0.name, "Float") }
    return types.flatMap { name, element in
        ShaderLanguage.intrinsics.compactMap { intrinsic -> AdvertisedCall? in
            let isVector = vectors.contains { $0.name == name }
            if intrinsic.reducesToScalar && !isVector { return nil }
            let arguments = Array(repeating: "input[gid]", count: intrinsic.arity).joined(separator: ", ")
            return AdvertisedCall(
                type: name,
                resultType: intrinsic.reducesToScalar ? element : name,
                expression: "\(intrinsic.name)(\(arguments))"
            )
        }
    }
}

@Test(arguments: advertisedIntrinsicCalls())
func `advertised intrinsics type check and compile`(call: AdvertisedCall) throws {
    try withShader("""
    import Schmetal
    @compute
    func use(output: Buffer<\(call.resultType)>, input: Buffer<\(call.type)>, gid: GridIndex) {
        output[gid] = \(call.expression)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

private func advertisedConstructorCalls() -> [AdvertisedCall] {
    ShaderLanguage.vectorTypes.map { vector in
        let literals = (1...vector.components.count).map(String.init).joined(separator: ", ")
        return AdvertisedCall(type: vector.name, resultType: vector.name, expression: "\(vector.name)(\(literals))")
    }
}

@Test(arguments: advertisedConstructorCalls())
func `advertised vector types construct and read components`(call: AdvertisedCall) throws {
    let vector = ShaderLanguage.vectorTypes.first { $0.name == call.type }!
    let reads = vector.components.map { "value.\($0)" }.joined(separator: " + ")
    try withShader("""
    import Schmetal
    @compute
    func use(output: Buffer<\(vector.element == "Swift.Float" ? "Float" : "UInt32")>, gid: GridIndex) {
        let value = \(call.expression)
        output[gid] = \(reads)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test
func `every advertised type has a Metal spelling and a prelude declaration`() {
    for vector in ShaderLanguage.vectorTypes {
        #expect(ShaderLanguage.metalTypes[ShaderLanguage.qualified(vector.name)] == vector.metal)
        #expect(Prelude.source.contains("public struct \(vector.name) {"))
    }
    for name in ShaderLanguage.indexTypes.keys {
        let unqualified = String(name.dropFirst(ShaderLanguage.moduleName.count + 1))
        #expect(Prelude.source.contains("public struct \(unqualified)"))
    }
    for intrinsic in ShaderLanguage.intrinsics {
        #expect(Prelude.source.contains("public func \(intrinsic.name)("))
    }
}
