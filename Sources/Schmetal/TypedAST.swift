import Foundation

public struct SchmetalError: Error, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

struct ASTNode {
    let kind: String
    var fields: [String: String]
    var children: [ASTNode]

    subscript(field: String) -> String? { fields[field] }
    var type: String? { fields["type"] ?? fields["interface_type"] }
    var name: String? { fields["name"] ?? fields["value"] }
    var declBaseName: String? { fields["decl_name"] }
    var isImplicit: Bool { fields["implicit"] == "true" }
    func children(of kind: String) -> [ASTNode] { children.filter { $0.kind == kind } }
    func firstChild(of kind: String) -> ASTNode? { children.first { $0.kind == kind } }
    func firstDescendant(of kind: String) -> ASTNode? {
        if self.kind == kind { return self }
        return children.lazy.compactMap { $0.firstDescendant(of: kind) }.first
    }
}

struct TypedAST {
    let path: String
    let source: String
    let declarations: [ASTNode]
    let shaderCompilerPath: String
    let preludeCompilerPath: String
    let symbols: [String: DemangledSymbol]
    let declarationsByUSR: [String: ASTNode]

    var identifiers: Set<String> {
        func collect(_ node: ASTNode) -> [String] {
            let name = node.name.map { String($0.prefix { $0 != "(" }) }
            return [name].compactMap { $0 } + node.children.flatMap(collect)
        }
        return Set(declarations.flatMap(collect))
    }

    var structures: [ASTNode] {
        func collect(_ nodes: [ASTNode]) -> [ASTNode] {
            nodes.filter { $0.kind == "struct_decl" && !$0.isImplicit }.flatMap { collect($0.children) + [$0] }
        }
        return collect(declarations)
    }

    init(path: String, strict: Bool = true) throws {
        self.path = path
        source = try String(contentsOfFile: path, encoding: .utf8)
        let staged = try Prelude.stage(shaderPath: path)
        shaderCompilerPath = staged.shader.path
        preludeCompilerPath = staged.prelude.path
        defer { try? FileManager.default.removeItem(at: staged.directory) }
        let dump: SwiftFrontend.Dump
        do {
            dump = try SwiftFrontend.dumpAST(
                files: [staged.prelude.path, staged.shader.path], shaderName: staged.shader.lastPathComponent
            )
        } catch let error as SchmetalError {
            throw SchmetalError(error.description.replacing(staged.shader.path, with: path))
        }
        guard let file = dump.shaderFile else { throw SchmetalError("swiftc produced no AST for \(path)") }
        symbols = dump.symbols
        var bindings = LocalBindings()
        func originalLocations(_ original: ASTNode) -> ASTNode {
            var node = original
            node.fields["location"] = node["location"]?.replacing(staged.shader.path, with: path)
            node.children = node.children.map(originalLocations)
            return node
        }
        declarations = try bindings.resolve(file.children.map(originalLocations))
        var registry = [String: ASTNode]()
        func register(_ node: ASTNode) {
            if let usr = node["usr"], !usr.isEmpty { registry[usr] = node }
            for child in node.children { register(child) }
        }
        for file in dump.files { register(file) }
        declarationsByUSR = registry
    }
}

enum SwiftFrontend {
    struct Dump {
        let files: [ASTNode]
        let shaderFile: ASTNode?
        let symbols: [String: DemangledSymbol]
    }

    static func dumpAST(files: [String], shaderName: String) throws -> Dump {
        let sdkOutput = try ToolProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--show-sdk-path"]
        )
        let sdk = sdkOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        var objects = [[String: Any]]()
        for file in files {
            let output = try ToolProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["swiftc", "-frontend", "-dump-ast", "-dump-ast-format", "json", "-sdk", sdk,
                            "-module-name", ShaderLanguage.moduleName, "-primary-file", file] + files.filter { $0 != file }
            )
            let decoded = try JSONSerialization.jsonObject(with: Data(output.standardOutput.utf8))
            guard let object = decoded as? [String: Any], object["_kind"] as? String == "source_file" else {
                throw SchmetalError("expected a JSON source_file from swiftc")
            }
            objects.append(object)
        }
        let identities = JSONASTDecoder.identities(in: objects)
        let symbols = try DemangledSymbol.load(identities)
        let sources = try Dictionary(uniqueKeysWithValues: files.map { file in
            (file, Array(try Data(contentsOf: URL(fileURLWithPath: file))))
        })
        let decoded = try zip(files, objects).map { file, object in
            try JSONASTDecoder(symbols: symbols, file: file, source: sources[file] ?? [], otherSources: sources)
                .decode(object)
        }
        return Dump(files: decoded, shaderFile: decoded.first {
            ($0["filename"] as NSString?)?.lastPathComponent == shaderName
        }, symbols: symbols)
    }
}
