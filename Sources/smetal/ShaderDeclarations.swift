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
            case "var_decl":
                guard node["let"] != nil else {
                    throw SMetalError("mutable globals are unsupported")
                }
                try validateProperty(node, allowWrapper: false)
            case "pattern_binding_decl":
                try validateBinding(node)
            case "struct_decl":
                try validateStructure(node)
            case "func_decl":
                guard let name = node.name?.split(separator: "(").first,
                      name.first?.isLetter == true || name.first == "_" else {
                    throw SMetalError("custom operator declarations are unsupported")
                }
                guard node["async"] == nil, node["throws"] == nil,
                      node.type?.contains(" async ") != true,
                      node["thrown_type"] == "<null>",
                      node.children(of: "custom_attr").count <= 1 else {
                    throw SMetalError("unsupported function effects or attributes")
                }
            default:
                throw SMetalError("unsupported top-level declaration: \(node.kind)")
            }
        }
    }

    private func validateStructure(_ node: ASTNode) throws {
        for member in node.children where !member.isImplicit {
            switch member.kind {
            case "var_decl":
                try validateProperty(member, allowWrapper: true)
            case "pattern_binding_decl":
                try validateBinding(member)
            default:
                throw SMetalError("unsupported struct member: \(member.kind)")
            }
        }
    }

    func functionName(_ node: ASTNode) throws -> String {
        guard let index = functions.firstIndex(where: { $0.name == node.name && $0.type == node.type }),
              let signature = node.name else {
            throw SMetalError("unregistered shader function")
        }
        if node.firstChild(of: "custom_attr") != nil {
            return String(signature.prefix { $0 != "(" })
        }
        return "smetal_helper_\(index)"
    }

    func helperName(for reference: ASTNode) throws -> String? {
        guard isFrom(reference, path: ast.shaderCompilerPath) else {
            return nil
        }
        let identity = declarationIdentity(reference)
        guard let function = functions.first(where: {
            identity == "SMetalShader.(file).\($0.name ?? "")" && $0.type == reference.type
        }) else {
            throw SMetalError("unsupported shader callee: \(identity)")
        }
        guard function.firstChild(of: "custom_attr") == nil else {
            throw SMetalError("calling shader entry points is unsupported")
        }
        return try functionName(function)
    }

    func isPreludeFunction(_ reference: ASTNode, name: String) -> Bool {
        guard isFrom(reference, path: ast.preludeCompilerPath) else {
            return false
        }
        let identity = declarationIdentity(reference)
        return identity == "SMetalShader.(file).\(name)"
            || identity.hasPrefix("SMetalShader.(file).\(name)(")
    }

    func isSwiftIntrinsic(_ reference: ASTNode, name: String) -> Bool {
        ["min", "max", "abs"].contains(name) && declarationIdentity(reference) == "Swift.(file).\(name)"
    }

    func validateOperator(_ reference: ASTNode, name: String) throws {
        let identity = declarationIdentity(reference)
        let scalars = ["Float", "Double", "Float16", "Int", "Int32", "UInt", "UInt32", "Bool"]
        if scalars.contains(where: {
            identity == "Swift.(file).\($0) extension.\(name)" || identity == "Swift.(file).\($0).\(name)"
        }) {
            return
        }
        let comparisons = ["<", ">", "<=", ">=", "==", "!="]
        let protocols = ["Comparable", "Equatable"]
        if comparisons.contains(name),
           protocols.contains(where: { identity == "Swift.(file).\($0).\(name)" }),
           let substitutions = reference["decl"]?.components(separatedBy: "Self -> ").last,
           scalars.contains(String(substitutions.prefix { $0 != ")" })) {
            return
        }
        let vectors = ["Float2", "Float3", "Float4"]
        if isFrom(reference, path: ast.preludeCompilerPath),
           vectors.contains(where: { identity == "SMetalShader.(file).\($0).\(name)" }) {
            return
        }
        throw SMetalError("unsupported operator declaration: \(identity)")
    }

    func validateConstructor(_ reference: ASTNode, typeName: String, shaderStruct: Bool) throws {
        let identity = declarationIdentity(reference)
        let expected = "SMetalShader.(file).\(typeName).init"
        if isFrom(reference, path: shaderStruct ? ast.shaderCompilerPath : ast.preludeCompilerPath),
           identity.hasPrefix(expected + "(") || identity == expected {
            return
        }
        let scalar = typeName == "Half" ? "Float16" : typeName
        if !shaderStruct, identity.hasPrefix("Swift.(file).\(scalar) extension.init(") {
            return
        }
        throw SMetalError("unsupported constructor declaration: \(identity)")
    }

    func validateBinding(_ node: ASTNode) throws {
        let entries = node.children(of: "pattern_entry")
        guard entries.count == 1, let entry = entries.first,
              entry.firstDescendant(of: "pattern_tuple") == nil,
              entry.firstDescendant(of: "pattern_named") != nil else {
            throw SMetalError("only single named bindings are supported")
        }
    }

    func validateMember(_ reference: ASTNode) throws {
        let identity = declarationIdentity(reference)
        if isFrom(reference, path: ast.shaderCompilerPath) {
            for structure in ast.declarations where structure.kind == "struct_decl" {
                for property in structure.children(of: "var_decl") where !property.isImplicit {
                    if identity == "SMetalShader.(file).\(structure.name ?? "").\(property.name ?? "")" {
                        return
                    }
                }
            }
        }
        if isFrom(reference, path: ast.preludeCompilerPath) {
            let vectorMembers = ["Float2": ["x", "y"], "Float3": ["x", "y", "z"],
                                 "Float4": ["x", "y", "z", "w"], "UInt2": ["x", "y"], "UInt3": ["x", "y", "z"]]
            for (type, members) in vectorMembers where members.contains(where: {
                identity == "SMetalShader.(file).\(type).\($0)"
            }) {
                return
            }
        }
        throw SMetalError("unsupported member declaration: \(identity)")
    }

    func validateSubscript(_ reference: ASTNode) throws {
        guard isFrom(reference, path: ast.preludeCompilerPath),
              declarationIdentity(reference) == "SMetalShader.(file).Buffer.subscript(_:)" else {
            throw SMetalError("only Buffer subscripts are supported")
        }
    }

    func validateProperty(_ node: ASTNode, allowWrapper: Bool) throws {
        guard node["static"] == nil,
              node.children(of: "accessor_decl").allSatisfy(\.isImplicit) else {
            throw SMetalError("computed, observed, and static properties are unsupported")
        }
        let wrappers = node.children(of: "custom_attr")
        guard wrappers.isEmpty || (allowWrapper && wrappers.count == 1) else {
            throw SMetalError("unsupported property attributes")
        }
        if !allowWrapper, node["readImpl"] != "stored" {
            throw SMetalError("only stored global constants are supported")
        }
    }

    private func isFrom(_ reference: ASTNode, path: String) -> Bool {
        reference["decl"]?.contains("@\(path):") == true
    }

    private func declarationIdentity(_ reference: ASTNode) -> String {
        let declaration = reference["decl"] ?? ""
        let withoutSubstitutions = declaration.components(separatedBy: " [with")[0]
        return String(withoutSubstitutions.prefix { $0 != "@" })
    }
}
