import Foundation

struct DemangledSymbol {
    let kind: String
    let text: String?
    let children: [DemangledSymbol]

    var typeName: String? {
        switch kind {
        case "Global", "TypeMangling", "Type", "ArgumentTuple", "ReturnType":
            return children.first?.typeName
        case "Module":
            return text
        case "Structure", "Enum", "Class", "Protocol":
            guard children.count == 2, let context = children[0].typeName,
                  children[1].kind == "Identifier", let name = children[1].text else { return nil }
            return context + "." + name
        case "BoundGenericStructure", "BoundGenericEnum", "BoundGenericClass":
            guard children.count == 2, let base = children[0].typeName, children[1].kind == "TypeList" else {
                return nil
            }
            let arguments = children[1].children.compactMap(\.typeName)
            guard arguments.count == children[1].children.count else { return nil }
            return base + "<" + arguments.joined(separator: ", ") + ">"
        case "Metatype":
            return children.first?.typeName.map { $0 + ".Type" }
        case "Tuple" where children.isEmpty:
            return "()"
        case "Extension":
            return children.dropFirst().first?.typeName
        default:
            return nil
        }
    }

    var instanceType: String? {
        if kind == "Metatype" { return children.first?.typeName }
        if ["Global", "TypeMangling", "Type"].contains(kind) { return children.first?.instanceType }
        return nil
    }

    var declarationOwner: String? {
        if ["Function", "Constructor", "Allocator", "Variable", "Subscript"].contains(kind) {
            return children.first?.typeName
        }
        if ["Global", "Static", "Getter", "Setter", "ModifyAccessor"].contains(kind) {
            return children.first?.declarationOwner
        }
        return nil
    }

    func contains(_ kind: String) -> Bool {
        self.kind == kind || children.contains { $0.contains(kind) }
    }

    static func load(_ identities: Set<String>) throws -> [String: DemangledSymbol] {
        let identities = identities.filter { $0.hasPrefix("$s") || $0.hasPrefix("s:") }.sorted()
        var result: [String: DemangledSymbol] = [:]
        for start in stride(from: 0, to: identities.count, by: 64) {
            let batch = Array(identities[start..<min(start + 64, identities.count)])
            let mangled = batch.map { $0.hasPrefix("s:") ? "$s" + $0.dropFirst(2) : $0 }
            let output = try ToolProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["swift-demangle", "--expand", "--tree-only"] + mangled
            )
            let sections = output.standardOutput.components(separatedBy: "Demangling for ").dropFirst()
            guard sections.count == batch.count else { throw SMetalError("unexpected swift-demangle output") }
            for (identity, section) in zip(batch, sections) {
                let lines = section.split(separator: "\n").dropFirst().filter { $0.contains("kind=") }
                var index = 0
                let rows = lines.map(String.init)
                if !rows.isEmpty { result[identity] = try parse(rows, index: &index, depth: 0) }
                guard index == rows.count else { throw SMetalError("malformed demangled symbol tree") }
            }
        }
        return result
    }

    private static func parse(_ rows: [String], index: inout Int, depth: Int) throws -> DemangledSymbol {
        let line = rows[index]
        guard line.prefix(while: { $0 == " " }).count == depth else {
            throw SMetalError("unexpected demangler indentation")
        }
        let content = String(line.dropFirst(depth))
        guard content.hasPrefix("kind=") else { throw SMetalError("missing demangler node kind") }
        let kind = String(content.dropFirst(5).prefix { $0 != "," })
        var text: String?
        if let range = content.range(of: ", text=") {
            let encoded = Data(content[range.upperBound...].utf8)
            text = try JSONSerialization.jsonObject(with: encoded, options: .fragmentsAllowed) as? String
        }
        index += 1
        var children: [DemangledSymbol] = []
        while index < rows.count, rows[index].prefix(while: { $0 == " " }).count > depth {
            children.append(try parse(rows, index: &index, depth: depth + 2))
        }
        return DemangledSymbol(kind: kind, text: text, children: children)
    }
}
