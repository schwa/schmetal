import Foundation
import Testing
@testable import Schmetal

func withShader(_ source: String, body: (String) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "test.schmetal")
    try source.write(to: file, atomically: true, encoding: .utf8)
    try body(file.path)
}

@Test func `buffer vector subscript and scalar multiplication compile`() throws {
    try withShader("""
    import Schmetal
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
    import Schmetal
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
    import Schmetal
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
    try withShader("import Schmetal\nfunc bad(value: MissingType) {}") { path in
        #expect(throws: SchmetalError.self) { try TypedAST(path: path) }
    }
}

@Test func `vector buffer cannot be assigned to scalar`() throws {
    try withShader("""
    import Schmetal
    func bad(values: Buffer<Float4>) {
        var value: Float = 0.0
        value = values[0]
    }
    """) { path in
        #expect(throws: SchmetalError.self) { try TypedAST(path: path) }
    }
}

@Test func `frontend rejects driver failures without source locations`() throws {
    let missing = "/tmp/schmetal-missing-\(UUID().uuidString).swift"
    do {
        _ = try SwiftFrontend.dumpAST(files: [missing], shaderName: "missing.swift")
        Issue.record("Frontend accepted a failed compiler invocation")
    } catch let error as SchmetalError {
        #expect(error.description.contains(missing))
        #expect(error.description.contains("error:"))
    }
}

@Test func `frontend failure keeps source context even in nonstrict mode`() throws {
    try withShader("import Schmetal\nfunc bad(value: MissingType) {}") { path in
        do {
            _ = try TypedAST(path: path, strict: false)
            Issue.record("Accepted a failed type check in nonstrict mode")
        } catch let error as SchmetalError {
            #expect(error.description.contains("\(path):2:"))
            #expect(error.description.contains("MissingType"))
            #expect(error.description.contains("func bad(value: MissingType) {}"))
        }
    }
}

@Test(arguments: ["Float", "Double", "Half", "Float2", "Float3", "Float4"])
func `advertised floating point intrinsics compile to Metal`(type: String) throws {
    let calls = [
        "sqrt(value)", "sin(value)", "cos(value)", "floor(value)", "ceil(value)",
        "pow(value, value)", "min(value, value)", "max(value, value)",
        "abs(value)", "clamp(value, value, value)", "mix(value, value, weight)"
    ]
    let assignments = calls.map { "output[gid] = \($0)" }.joined(separator: "\n")
    let weightType = type.hasPrefix("Float") && type != "Float" ? "Float" : type
    try withShader("""
    import Schmetal
    @compute
    func math(input: Buffer<\(type)>, output: Buffer<\(type)>, weight: \(weightType), gid: GridIndex) {
        let value = input[gid]
        \(assignments)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        for call in calls {
            #expect(metal.contains(call))
        }
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test(arguments: ["Float2", "Float3", "Float4"])
func `dot and vector weighted mix compile to Metal`(type: String) throws {
    try withShader("""
    import Schmetal
    @compute
    func vectorMath(input: Buffer<\(type)>, output: Buffer<\(type)>, scalar: Buffer<Float>, gid: GridIndex) {
        let value = input[gid]
        scalar[gid] = dot(value, value)
        output[gid] = mix(value, value, value)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("dot(value, value)"))
        #expect(metal.contains("mix(value, value, value)"))
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test(arguments: ["sqrt(true)", "pow(value, true)", "dot(value, value)", "sin(value, value)"])
func `math intrinsic invalid arguments are rejected`(expression: String) throws {
    try withShader("""
    import Schmetal
    @compute
    func invalid(input: Buffer<Float>, output: Buffer<Float>, gid: GridIndex) {
        let value = input[gid]
        output[gid] = \(expression)
    }
    """) { path in
        #expect(throws: SchmetalError.self) { try TypedAST(path: path) }
    }
}

@Test(arguments: [
    "struct Value { var x: Float; func ignored() {} }",
    "struct Value { var x: Float { 42.0 } }",
    "import Foundation\nfunc external() -> Float { Float.random(in: 0...1) }",
    "func indirect(operation: (Float) -> Float, value: Float) -> Float { operation(value) }",
    "var mutableGlobal: Float = 1.0",
    "struct Value { static var x: Float = 1.0 }",
    "func /(_ left: Float4, _ right: Float4) -> Float4 { left }",
    "func asynchronous() async {}",
    "func observed() { var value: Float = 0 { didSet {} }; value = 1 }",
    "let first: Float = 1, second: Float = 2"
])
func `unsupported declarations and callees are rejected before Metal emission`(source: String) throws {
    try withShader("import Schmetal\n" + source) { path in
        let ast = try TypedAST(path: path)
        #expect(throws: SchmetalError.self) {
            var emitter = Emitter(ast: ast)
            _ = try emitter.emit()
        }
    }
}

@Test func `helper overloads retain identity instead of becoming Metal intrinsics`() throws {
    try withShader("""
    import Schmetal
    @compute
    func entry(output: Buffer<Float>, gid: GridIndex) {
        output[gid] = sin(value: 1.0) + sin(other: 2.0) + sin(0.0)
    }
    func sin(value: Float) -> Float { value + 10.0 }
    func sin(other: Float) -> Float { other + 20.0 }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("schmetal_helper_1(1.0)"))
        #expect(metal.contains("schmetal_helper_2(2.0)"))
        #expect(metal.contains("sin(0.0)"))
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test func `supported constructors preserve declaration identity`() throws {
    try withShader("""
    import Schmetal
    struct Pair { var value: Float }
    @compute
    func construct(output: Buffer<Float4>, gid: GridIndex) {
        let scalar = Float(2)
        let pair = Pair(value: scalar)
        output[gid] = Float4(pair.value, scalar, scalar, scalar)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test func `boolean conditions retain every clause during lowering`() throws {
    try withShader("""
    import Schmetal
    @compute
    func conditional(input: Buffer<Float>, output: Buffer<Float>, gid: GridIndex) {
        let value = input[gid]
        if value > 0, value < 1 { output[gid] = value }
        var count: Int = 0
        while count < 2 { count = count + 1 }
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        #expect(metal.contains("&&"))
        #expect(metal.contains("value > 0"))
        #expect(metal.contains("value < 1"))
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test(arguments: [
    "let flag = value > 0 && value < 10; output[gid] = flag ? value : 0",
    "let flag = value < 0 || value > 10; output[gid] = !flag ? value : -value",
    """
    var count: Int = 0
    var result = value
    while count < 3 { result = result + 1; count = count + 1 }
    output[gid] = result
    """,
    "if value < 0 { output[gid] = -value } else if value > 10 { output[gid] = 10 } else { output[gid] = (value + 1) }",
    "let flag: Bool = true; output[gid] = flag ? +value : 0"
])
func `control flow and scalar expressions compile to Metal`(body: String) throws {
    try withShader("""
    import Schmetal
    @compute
    func expressions(input: Buffer<Float>, output: Buffer<Float>, gid: GridIndex) {
        let value = input[gid]
        \(body)
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        for marker in ["&&", "||", "?", "while", "else"] where body.contains(marker) {
            #expect(metal.contains(marker))
        }
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test func `all advertised member attributes compile in stage structs`() throws {
    try withShader("""
    import Schmetal
    struct Vertex {
        @position var position: Float4
        @pointSize var size: Float
        @flat var identifier: UInt32
        var tint: Float4
    }
    struct Fragment {
        @color var first: Float4
        @color var second: Float4
    }
    @vertex
    func vertexMain(id: VertexIndex, positions: Buffer<Float4>) -> Vertex {
        var result: Vertex
        result.position = positions[id]
        result.size = 1
        result.identifier = 0
        result.tint = Float4(1, 0, 0, 1)
        return result
    }
    @fragment
    func fragmentMain(input: Vertex) -> Fragment {
        var result: Fragment
        result.first = input.tint
        result.second = input.tint
        return result
    }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        for attribute in ["position", "point_size", "flat", "color(0)", "color(1)"] {
            #expect(metal.contains("[[\(attribute)]]"))
        }
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}

@Test(arguments: [
    "func bad(values: Buffer<Float>) -> Float { values[1.5] }",
    "func bad(value: Float4) -> Float { value.q }",
    "func bad() -> Float4 { Float4(1, 2) }",
    "func bad(value: Float) -> Float { value ? 1 : 0 }",
    "func bad(value: Float) -> Bool { value && true }",
    "struct Bad { @unknown var value: Float }"
])
func `invalid shader language constructs fail type checking`(source: String) throws {
    try withShader("import Schmetal\n" + source) { path in
        #expect(throws: SchmetalError.self) { try TypedAST(path: path) }
    }
}

@Test(arguments: [
    ("Float", "Float(2)"), ("Int", "Int(2.0)"), ("UInt", "UInt(2)"),
    ("Half", "Half(2)"), ("Float2", "Float2(1, 2)"), ("Float3", "Float3(1, 2, 3)"),
    ("UInt2", "UInt2(1, 2)"), ("UInt3", "UInt3(1, 2, 3)")
])
func `advertised scalar and vector constructors compile`(type: String, expression: String) throws {
    try withShader("""
    import Schmetal
    @compute
    func construct(output: Buffer<\(type)>, gid: GridIndex) { output[gid] = \(expression) }
    """) { path in
        var emitter = Emitter(ast: try TypedAST(path: path))
        let metal = try emitter.emit()
        let metalPath = path + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: path + ".metallib")
    }
}
