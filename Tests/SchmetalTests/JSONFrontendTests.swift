import Foundation
import Testing
@testable import schmetal

@Test func `demangler distinguishes canonical scalar and generic identities`() throws {
    let symbols = try DemangledSymbol.load(["$sSfD", "$s13SchmetalProbe5FloatVD", "$s13SchmetalProbe6BufferVySfGD"])
    #expect(symbols["$sSfD"]?.typeName == "Swift.Float")
    #expect(symbols["$s13SchmetalProbe5FloatVD"]?.typeName == "SchmetalProbe.Float")
    #expect(symbols["$s13SchmetalProbe6BufferVySfGD"]?.typeName == "SchmetalProbe.Buffer<Swift.Float>")
}

@Test func `JSON source offsets preserve UTF8 columns and original shader paths`() throws {
    try withShader("""
    import Schmetal
    // 🧪
    func inspect(_ value: Float) -> Float { let café = value; return café }
    """) { path in
        let ast = try TypedAST(path: path)
        let function = try #require(ast.declarations.first { $0.kind == "func_decl" })
        let statement = try #require(function.firstDescendant(of: "return_stmt"))
        let reference = try #require(statement.firstDescendant(of: "declref_expr"))
        let expected = "func inspect(_ value: Float) -> Float { let café = value; return ".utf8.count + 1
        #expect(reference["location"] == "\(path):3:\(expected)")
        #expect(reference.type == "Swift.Float")
        #expect(reference["type_usr"] == "$sSfD")
    }
}

@Test func `missing JSON expression children fail explicitly`() throws {
    let decoder = JSONASTDecoder(symbols: [:], file: "test.swift", source: [])
    #expect(throws: SchmetalError.self) {
        try decoder.decode(["_kind": "binary_expr", "type": "$sSfD"])
    }
    #expect(throws: SchmetalError.self) {
        try decoder.decode(["_kind": "integer_literal_expr"])
    }
}

@Test func `unrecognized mangled types cannot become Metal scalar names`() throws {
    let symbols = try DemangledSymbol.load(["$sNotARealTypeD"])
    #expect(symbols["$sNotARealTypeD"]?.typeName == nil)
    try withShader("import Schmetal\nfunc unsupported(_ value: Float?) {}") { path in
        let ast = try TypedAST(path: path)
        #expect(throws: SchmetalError.self) {
            var emitter = Emitter(ast: ast)
            _ = try emitter.emit()
        }
    }
}

@Test func `aliases expose identical type identities while same named structs do not`() throws {
    try withShader("""
    import Schmetal
    typealias Scalar = Swift.Float
    struct Float { var value: Swift.Float }
    func inspect(_ a: Scalar, _ b: Swift.Float, _ c: Float) {}
    """) { path in
        let ast = try TypedAST(path: path)
        let function = try #require(ast.declarations.first { $0.kind == "func_decl" })
        let parameters = try #require(function.firstChild(of: "parameter_list")).children
        #expect(parameters[0]["interface_type_usr"] == parameters[1]["interface_type_usr"])
        #expect(parameters[0]["interface_type_usr"] != parameters[2]["interface_type_usr"])
    }
}

@Test func `JSON ranges reject unknown buffers and honor known source buffers`() throws {
    let decoder = JSONASTDecoder(
        symbols: [:], file: "shader.swift", source: [], otherSources: ["support.swift": Array("\n42".utf8)]
    )
    let literal: [String: Any] = [
        "_kind": "integer_literal_expr", "value": "42",
        "range": ["start": 1, "end": 1, "buffer_id": "support.swift"]
    ]
    #expect(try decoder.decode(literal)["location"] == "support.swift:2:1")
    #expect(throws: SchmetalError.self) {
        try decoder.decode(["_kind": "integer_literal_expr", "value": "42",
                            "range": ["start": 100, "end": 100]])
    }
    #expect(throws: SchmetalError.self) {
        try decoder.decode(["_kind": "integer_literal_expr", "value": "42",
                            "range": ["start": 0, "end": 0, "buffer_id": "unknown"]])
    }
}
