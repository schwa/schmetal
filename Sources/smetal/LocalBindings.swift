import Foundation

struct LocalBindings {
    private var nextID = 0
    private var usedNames = Set<String>()

    mutating func resolve(_ declarations: [ASTNode]) throws -> [ASTNode] {
        func names(_ node: ASTNode) -> [String] { [node.name].compactMap { $0 } + node.children.flatMap(names) }
        usedNames = Set(declarations.flatMap(names))
        let globals = declarations.filter { $0.kind == "var_decl" }.compactMap(\.name)
        return try declarations.map { declaration in
            guard declaration.kind == "func_decl" else { return declaration }
            var function = declaration
            var environment = Dictionary(uniqueKeysWithValues: globals.map { ($0, $0) })
            for index in function.children.indices where function.children[index].kind == "parameter_list" {
                for parameter in function.children[index].children.indices {
                    if let name = function.children[index].children[parameter].name {
                        let emitted = bind(name, environment: &environment)
                        function.children[index].children[parameter].fields["name"] = emitted
                    }
                }
            }
            for index in function.children.indices where function.children[index].kind == "brace_stmt" {
                function.children[index] = try rewrite(function.children[index], environment: &environment)
            }
            return function
        }
    }

    private mutating func bind(_ name: String, environment: inout [String: String]) -> String {
        var emitted = name
        if environment[name] != nil {
            repeat {
                emitted = "smetal_local_\(nextID)"
                nextID += 1
            } while usedNames.contains(emitted)
            usedNames.insert(emitted)
        }
        environment[name] = emitted
        return emitted
    }

    private mutating func rewrite(_ original: ASTNode, environment: inout [String: String]) throws -> ASTNode {
        var node = original
        switch node.kind {
        case "brace_stmt":
            var scope = environment
            node.children = try node.children.map { try rewrite($0, environment: &scope) }
        case "pattern_binding_decl":
            node.children = try node.children.map { try rewriteBinding($0, environment: &environment) }
        case "var_decl":
            if let name = node.name, let emitted = environment[name] { node.fields["name"] = emitted }
        case "declref_expr" where node["decl"] == "":
            guard let name = node.declBaseName, let emitted = environment[name] else {
                throw SMetalError("unresolved local reference: \(node.declBaseName ?? "unknown")")
            }
            node.fields["decl_name"] = emitted
        default:
            node.children = try node.children.map { try rewrite($0, environment: &environment) }
        }
        return node
    }

    private mutating func rewriteBinding(_ original: ASTNode, environment: inout [String: String]) throws -> ASTNode {
        var entry = original
        // Initializers see the outer binding, not the newly declared shadow.
        for child in entry.children.indices where entry.children[child]["label"] == "processed_init" {
            entry.children[child] = try rewrite(entry.children[child], environment: &environment)
        }
        guard let name = entry.firstDescendant(of: "pattern_named")?.name else {
            return entry
        }
        let emitted = bind(name, environment: &environment)
        func renamePattern(_ original: ASTNode) -> ASTNode {
            var pattern = original
            if pattern.kind == "pattern_named" { pattern.fields["name"] = emitted }
            pattern.children = pattern.children.map(renamePattern)
            return pattern
        }
        for child in entry.children.indices where entry.children[child]["label"] == "pattern" {
            entry.children[child] = renamePattern(entry.children[child])
        }
        return entry
    }
}
