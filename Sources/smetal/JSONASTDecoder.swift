import CoreFoundation
import Foundation

struct JSONASTDecoder {
    let symbols: [String: DemangledSymbol]
    let file: String
    let source: [UInt8]
    var otherSources: [String: [UInt8]] = [:]

    private static let childFields: [String: [String]] = [
        "source_file": ["items"],
        "struct_decl": ["attrs", "members"], "class_decl": ["attrs", "members"],
        "enum_decl": ["attrs", "members"], "extension_decl": ["attrs", "members"],
        "func_decl": ["attrs", "params", "body"], "constructor_decl": ["attrs", "params", "body"],
        "accessor_decl": ["attrs", "params", "body"], "parameter_list": ["params"],
        "parameter": ["attrs"], "var_decl": ["attrs", "accessors"],
        "pattern_binding_decl": ["pattern_entries"], "pattern_entry": ["pattern", "processed_init"],
        "pattern_typed": ["sub_pattern"], "brace_stmt": ["elements"],
        "argument_list": ["args"], "argument": ["expr"], "assign_expr": ["dest", "src"],
        "return_stmt": ["result"], "if_stmt": ["conditions", "then_stmt", "else_stmt"],
        "while_stmt": ["conditions", "body"], "ternary_expr": ["cond_expr", "then_expr", "else_expr"],
        "autoclosure_expr": ["params", "single_expr_body"], "binary_expr": ["fn", "args"],
        "prefix_unary_expr": ["fn", "args"], "call_expr": ["fn", "args"],
        "constructor_ref_call_expr": ["fn", "args"], "dot_syntax_call_expr": ["fn", "args"],
        "member_ref_expr": ["base"], "subscript_expr": ["base", "args"]
    ]

    private static let requiredFields: [String: [String]] = [
        "func_decl": ["name", "interface_type", "params", "result"], "pattern_entry": ["pattern"],
        "struct_decl": ["name", "interface_type"], "var_decl": ["name", "interface_type"], "custom_attr": ["type"],
        "binary_expr": ["fn", "args"], "prefix_unary_expr": ["fn", "args"],
        "call_expr": ["fn", "args"], "constructor_ref_call_expr": ["fn", "args"],
        "subscript_expr": ["base", "args", "decl"], "member_ref_expr": ["decl"], "declref_expr": ["decl"],
        "assign_expr": ["dest", "src"], "if_stmt": ["conditions", "then_stmt"],
        "while_stmt": ["conditions", "body"], "ternary_expr": ["cond_expr", "then_expr", "else_expr"],
        "integer_literal_expr": ["value"], "float_literal_expr": ["value"], "boolean_literal_expr": ["value"]
    ]

    static func identities(in value: Any) -> Set<String> {
        if let text = value as? String, text.hasPrefix("$s") || text.hasPrefix("s:") { return [text] }
        if let values = value as? [Any] { return values.reduce(into: []) { $0.formUnion(identities(in: $1)) } }
        if let object = value as? [String: Any] { return identities(in: Array(object.values)) }
        return []
    }

    func decode(_ object: [String: Any], label: String? = nil) throws -> ASTNode {
        guard let kind = object["_kind"] as? String else { throw SMetalError("JSON AST node has no kind") }
        guard (Self.requiredFields[kind] ?? []).allSatisfy({ object[$0] != nil }) else {
            throw SMetalError("incomplete JSON AST node: \(kind)")
        }
        var fields = scalarFields(object)
        fields["source_file"] = file
        fields["label"] = label
        addTypes(object, fields: &fields)
        addName(object, fields: &fields)
        addReference(object, fields: &fields)
        if let range = object["range"] as? [String: Any] {
            fields["location"] = try location(range)
            fields["offset"] = (range["start"] as? Int).map(String.init)
        }
        let children = try (Self.childFields[kind] ?? ["sub_expr"]).flatMap {
            try decodeChildren(object[$0], label: $0)
        }
        return ASTNode(kind: kind, fields: fields, children: children)
    }

    private func decodeChildren(_ value: Any?, label: String) throws -> [ASTNode] {
        guard let value else { return [] }
        if let child = value as? [String: Any] {
            return [try decode(child, label: label)]
        }
        guard let array = value as? [[String: Any]] else {
            throw SMetalError("unexpected JSON AST child shape: \(label)")
        }
        let nodes = try array.map { try decode($0) }
        if label == "conditions" {
            return [ASTNode(kind: "array", fields: ["label": label], children: nodes)]
        }
        return nodes
    }

    private func scalarFields(_ object: [String: Any]) -> [String: String] {
        var fields = [String: String]()
        for (key, value) in object {
            if let text = value as? String { fields[key] = text }
            if let number = value as? NSNumber {
                let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                fields[key] = isBoolean ? (number.boolValue ? "true" : "false") : number.stringValue
            }
        }
        return fields
    }

    private func addTypes(_ object: [String: Any], fields: inout [String: String]) {
        for key in ["type", "interface_type", "result", "thrown_type"] {
            guard let identity = object[key] as? String else { continue }
            fields[key + "_usr"] = identity
            fields[key] = identity.isEmpty ? "<null>" : (symbols[identity]?.typeName ?? identity)
            if symbols[identity]?.contains("AsyncAnnotation") == true { fields["async"] = "true" }
        }
        if let identity = object["interface_type"] as? String {
            fields["instance_type"] = symbols[identity]?.instanceType
        }
        if object["_kind"] as? String == "type_expr", let identity = object["type"] as? String {
            fields["typerepr"] = symbols[identity]?.instanceType
        }
    }

    private func addName(_ object: [String: Any], fields: inout [String: String]) {
        guard let name = object["name"] as? [String: Any], let base = name["base_name"] as? [String: Any] else {
            return
        }
        fields["name"] = base["name"] as? String
        if let arguments = name["args"] as? [String] {
            let labels = arguments.map { ($0.isEmpty ? "_" : $0) + ":" }.joined()
            fields["name"] = (fields["name"] ?? "") + "(" + labels + ")"
        }
    }

    private func addReference(_ object: [String: Any], fields: inout [String: String]) {
        guard let reference = object["decl"] as? [String: Any] else { return }
        fields["decl"] = reference["decl_usr"] as? String
        fields["decl_name"] = reference["base_name"] as? String
        let substitutions = reference["substitutions"] as? [String: Any]
        let replacements = substitutions?["substitutions"] as? [[String: Any]] ?? []
        fields["substitution_types"] = replacements.compactMap {
            guard let identity = $0["replacement_type"] as? String else { return nil }
            return symbols[identity]?.typeName ?? identity
        }.joined(separator: "|")
    }

    private func location(_ range: [String: Any]) throws -> String {
        let origin = range["buffer_id"] as? String ?? file
        guard let bytes = origin == file ? source : otherSources[origin],
              let start = range["start"] as? Int, let end = range["end"] as? Int,
              start >= 0, end >= start, end <= bytes.count else {
            throw SMetalError("unsupported JSON source range or buffer: \(origin)")
        }
        let prefix = bytes.prefix(start)
        let line = prefix.filter { $0 == 10 }.count + 1
        let column = start - (prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0) + 1
        return "\(origin):\(line):\(column)"
    }
}
