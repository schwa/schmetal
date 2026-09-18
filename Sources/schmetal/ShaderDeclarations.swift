import Foundation

struct ShaderDeclarations {
    private let ast: TypedAST
    private let functions: [ASTNode]

    init(ast: TypedAST) {
        self.ast = ast
        functions = ast.declarations.filter { $0.kind == "func_decl" && !$0.isImplicit }
    }

    func validate() throws {
        for node in ast.declarations where !node.isImplicit {
            switch node.kind {
            case "typealias": break
            case "var_decl":
                guard node["let"] != nil else { throw SchmetalError("mutable globals are unsupported") }
                try validateProperty(node, allowWrapper: false)
            case "pattern_binding_decl": try validateBinding(node)
            case "struct_decl": try validateStructure(node)
            case "func_decl":
                guard let name = node.name?.split(separator: "(").first,
                      name.first?.isLetter == true || name.first == "_" else {
                    throw SchmetalError("custom operator declarations are unsupported")
                }
                guard node["async"] == nil, node["throws"] == nil, node["thrown_type"] == "<null>",
                      node.children(of: "custom_attr").count <= 1 else {
                    throw SchmetalError("unsupported function effects or attributes")
                }
            default: throw SchmetalError("unsupported top-level declaration: \(node.kind)")
            }
        }
    }

    private func validateStructure(_ node: ASTNode) throws {
        for member in node.children where !member.isImplicit {
            switch member.kind {
            case "typealias": break
            case "struct_decl": try validateStructure(member)
            case "var_decl": try validateProperty(member, allowWrapper: true)
            case "pattern_binding_decl":
                try validateBinding(member)
                guard !member.children(of: "pattern_entry").contains(where: { entry in
                    entry.children.contains { $0["label"] == "processed_init" }
                }) else { throw SchmetalError("stored property initializers are unsupported") }
            default: throw SchmetalError("unsupported struct member: \(member.kind)")
            }
        }
    }

    func functionName(_ node: ASTNode) throws -> String {
        guard let usr = node["usr"], let index = functions.firstIndex(where: { $0["usr"] == usr }),
              let signature = node.name else { throw SchmetalError("unregistered shader function") }
        if node.firstChild(of: "custom_attr") != nil { return String(signature.prefix { $0 != "(" }) }
        var name = "schmetal_helper_\(index)"
        while ast.identifiers.contains(name) { name += "_" }
        return name
    }

    func helperName(for reference: ASTNode) throws -> String? {
        guard let usr = reference["decl"], let function = functions.first(where: { $0["usr"] == usr }) else {
            return nil
        }
        guard function.firstChild(of: "custom_attr") == nil else {
            throw SchmetalError("calling shader entry points is unsupported")
        }
        return try functionName(function)
    }

    func isPreludeFunction(_ reference: ASTNode, name: String) -> Bool {
        registered(reference)?["source_file"] == ast.preludeCompilerPath
            && registered(reference)?.kind == "func_decl"
            && owner(reference) == "SchmetalShader" && reference.declBaseName == name
    }

    func isSwiftIntrinsic(_ reference: ASTNode, name: String) -> Bool {
        ["min", "max", "abs"].contains(name) && owner(reference) == "Swift" && reference.declBaseName == name
    }

    func validateOperator(_ reference: ASTNode, name: String) throws {
        let scalars = ["Float", "Double", "Float16", "Int", "Int32", "UInt", "UInt32", "Bool"].map { "Swift." + $0 }
        guard reference.declBaseName == name, let context = owner(reference) else {
            throw SchmetalError("unresolved operator identity")
        }
        if scalars.contains(context) { return }
        let replacements = reference["substitution_types"]?.split(separator: "|").map(String.init) ?? []
        if replacements.count == 1, replacements.allSatisfy(scalars.contains) {
            if name == "+", context == "Swift.AdditiveArithmetic" { return }
            let comparisons = ["<", ">", "<=", ">=", "==", "!="]
            if comparisons.contains(name), ["Swift.Comparable", "Swift.Equatable"].contains(context) {
                return
            }
        }
        if registered(reference)?["source_file"] == ast.preludeCompilerPath,
           ["SchmetalShader.Float2", "SchmetalShader.Float3", "SchmetalShader.Float4"].contains(context) { return }
        throw SchmetalError("unsupported operator declaration: \(reference["decl"] ?? name)")
    }

    func validateConstructor(_ reference: ASTNode, typeName: String, shaderStruct: Bool) throws {
        guard owner(reference) == typeName else { throw SchmetalError("constructor type identity mismatch") }
        if !shaderStruct, typeName.hasPrefix("Swift.") { return }
        let expected = shaderStruct ? ast.shaderCompilerPath : ast.preludeCompilerPath
        guard registered(reference)?["source_file"] == expected else {
            throw SchmetalError("unsupported constructor declaration: \(reference["decl"] ?? typeName)")
        }
    }

    func validateBinding(_ node: ASTNode) throws {
        let entries = node.children(of: "pattern_entry")
        guard entries.count == 1, let entry = entries.first,
              entry.firstDescendant(of: "pattern_tuple") == nil,
              entry.firstDescendant(of: "pattern_named") != nil else {
            throw SchmetalError("only single named bindings are supported")
        }
    }

    func validateMember(_ reference: ASTNode) throws {
        guard let declaration = registered(reference), declaration.kind == "var_decl" else {
            throw SchmetalError("unsupported member identity")
        }
        if declaration["source_file"] == ast.shaderCompilerPath { return }
        let vectors = ["Float2", "Float3", "Float4", "UInt2", "UInt3"].map { "SchmetalShader." + $0 }
        guard declaration["source_file"] == ast.preludeCompilerPath, vectors.contains(owner(reference) ?? ""),
              ["x", "y", "z", "w"].contains(reference.declBaseName ?? "") else {
            throw SchmetalError("unsupported member declaration: \(reference["decl"] ?? "unknown")")
        }
    }

    func validateSubscript(_ reference: ASTNode) throws {
        guard registered(reference)?["source_file"] == ast.preludeCompilerPath,
              owner(reference) == "SchmetalShader.Buffer", reference.declBaseName == "subscript" else {
            throw SchmetalError("only Buffer subscripts are supported")
        }
    }

    func validateProperty(_ node: ASTNode, allowWrapper: Bool) throws {
        guard node["static"] == nil, node.children(of: "accessor_decl").allSatisfy(\.isImplicit) else {
            throw SchmetalError("computed, observed, and static properties are unsupported")
        }
        let wrappers = node.children(of: "custom_attr")
        guard wrappers.isEmpty || (allowWrapper && wrappers.count == 1) else {
            throw SchmetalError("unsupported property attributes")
        }
        if !allowWrapper, node["readImpl"] != "stored" {
            throw SchmetalError("only stored global constants are supported")
        }
    }

    private func registered(_ reference: ASTNode) -> ASTNode? { ast.declarationsByUSR[reference["decl"] ?? ""] }
    private func owner(_ reference: ASTNode) -> String? { ast.symbols[reference["decl"] ?? ""]?.declarationOwner }
}
