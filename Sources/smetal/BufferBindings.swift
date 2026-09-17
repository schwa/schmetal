import Foundation

struct BufferBindings {
    private(set) var slots: [String: Int] = [:]
    private static let validSlots = 0...30

    init(parameters: [ASTNode], automaticResources: Set<String>, nonBindable: Set<String>, isEntryPoint: Bool) throws {
        var used = Set<Int>()
        for parameter in parameters {
            guard let name = parameter.name else { throw SMetalError("unnamed binding parameter") }
            guard let slot = try Self.explicitSlot(parameter, name: name) else { continue }
            guard isEntryPoint, !nonBindable.contains(name) else {
                throw SMetalError("@buffer requires a resource parameter on an entry point: '\(name)'")
            }
            guard used.insert(slot).inserted else { throw SMetalError("duplicate buffer slot \(slot)") }
            slots[name] = slot
        }
        guard isEntryPoint else { return }
        for parameter in parameters {
            guard let name = parameter.name, automaticResources.contains(name), slots[name] == nil else { continue }
            guard let slot = Self.validSlots.first(where: { !used.contains($0) }) else {
                throw SMetalError("entry point requires more than 31 buffer bindings")
            }
            slots[name] = slot
            used.insert(slot)
        }
    }

    private static func explicitSlot(_ parameter: ASTNode, name: String) throws -> Int? {
        let attributes = parameter.children(of: "custom_attr")
        guard !attributes.isEmpty else { return nil }
        guard attributes.count == 1, let attribute = attributes.first, attribute.type == "SMetalShader.buffer" else {
            throw SMetalError("unsupported parameter attribute on '\(name)'")
        }
        let arguments = attribute.firstChild(of: "argument_list")?.children(of: "argument") ?? []
        let invalid = SMetalError("@buffer on '\(name)' requires an integer literal from 0 through 30")
        guard arguments.count == 1, let argument = arguments.first, argument.children.count == 1,
              let value = argument.children.first, value.kind == "integer_literal_expr",
              let text = value["value"], let magnitude = integerLiteral(text), magnitude >= 0 else {
            throw invalid
        }
        let slot = value["negative"] == "true" ? -magnitude : magnitude
        guard validSlots.contains(slot) else { throw invalid }
        return slot
    }

    private static func integerLiteral(_ text: String) -> Int? {
        let radix = ["0x": 16, "0o": 8, "0b": 2][String(text.prefix(2))] ?? 10
        let digits = radix == 10 ? text : String(text.dropFirst(2))
        return Int(digits, radix: radix)
    }
}
