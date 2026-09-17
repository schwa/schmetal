import Foundation

struct SMetalError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// One node of swiftc's post-type-check AST dump.
struct ASTNode {
    var kind: String
    var fields: [String: String]
    var children: [ASTNode]

    subscript(field: String) -> String? { fields[field] }

    var type: String? { fields["type"] ?? fields["interface_type"] }
    var name: String? { fields["name"] ?? fields["value"] }

    /// Trailing identifier of a `decl` reference: `demo.(file).Buffer.subscript(_:)` → `subscript(_:)`.
    var declBaseName: String? {
        guard let decl = fields["decl"] else { return nil }
        let withoutSubstitutions = decl.split(separator: " [with").first.map(String.init) ?? decl
        let withoutLocation = withoutSubstitutions.split(separator: "@").first.map(String.init) ?? withoutSubstitutions
        return withoutLocation.split(separator: ".").last.map(String.init)
    }

    func children(of kind: String) -> [ASTNode] { children.filter { $0.kind == kind } }
    func firstChild(of kind: String) -> ASTNode? { children.first { $0.kind == kind } }

    /// Depth-first search, used to reach through the implicit wrappers swiftc
    /// inserts (`load_expr`, `dot_syntax_call_expr`, argument lists).
    func firstDescendant(of kind: String) -> ASTNode? {
        if self.kind == kind { return self }
        for child in children {
            if let found = child.firstDescendant(of: kind) { return found }
        }
        return nil
    }

    var isImplicit: Bool { fields["implicit"] != nil }
}

/// Type-checked AST of a .smetal file, produced by `swiftc -dump-ast`.
struct TypedAST {
    let path: String
    let source: String
    /// Top-level declarations of the shader file only; the prelude is dropped.
    let declarations: [ASTNode]

    init(path: String, strict: Bool = true) throws {
        self.path = path
        source = try String(contentsOfFile: path, encoding: .utf8)

        let staged = try Prelude.stage(shaderPath: path)
        defer { try? FileManager.default.removeItem(at: staged.directory) }

        let dump: SwiftFrontend.Dump
        do {
            dump = try SwiftFrontend.dumpAST(
                files: [staged.prelude.path, staged.shader.path],
                shaderName: staged.shader.lastPathComponent
            )
        } catch let error as SMetalError {
            throw SMetalError(error.description.replacing(staged.shader.path, with: path))
        }

        if !dump.diagnostics.isEmpty {
            let report = dump.diagnostics
                .map { "  \(path):\($0.line):\($0.column): \($0.severity): \($0.message)" }
                .joined(separator: "\n")
            let errors = dump.diagnostics.filter { $0.severity == "error" }
            if !errors.isEmpty {
                if strict { throw SMetalError("\(errors.count) error(s):\n\(report)") }
                FileHandle.standardError.write(Data("smetal: warning: \(report)\n".utf8))
            }
        }

        guard let file = dump.shaderFile else {
            throw SMetalError("swiftc produced no AST for \(path)")
        }
        declarations = file.children
    }
}

/// Runs `swiftc -dump-ast` and parses the s-expression dump.
enum SwiftFrontend {
    struct Diagnostic {
        var line: Int
        var column: Int
        var severity: String
        var message: String
    }

    struct Dump {
        var files: [ASTNode]
        var diagnostics: [Diagnostic]
        var shaderFile: ASTNode?
    }

    static func dumpAST(files: [String], shaderName: String) throws -> Dump {
        // -dump-ast writes the tree to stderr and rejects both -o and -wmo, so
        // the dump and the diagnostics arrive interleaved on the same stream.
        let raw = try run("swiftc", ["-dump-ast", "-module-name", "SMetalShader"] + files)

        var astLines: [String] = []
        var diagnostics: [Diagnostic] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if let diagnostic = parseDiagnostic(String(line)) {
                diagnostics.append(diagnostic)
            } else {
                astLines.append(String(line))
            }
        }

        var parser = SExpressionParser(text: astLines.joined(separator: "\n"))
        let files = try parser.parseSourceFiles()
        // swiftc echoes the path exactly as given, so match on the basename.
        let shader = files.first {
            ($0["filename"] as NSString?)?.lastPathComponent == shaderName
        }
        return Dump(files: files, diagnostics: diagnostics, shaderFile: shader)
    }

    static func parseDiagnostic(_ line: String) -> Diagnostic? {
        let pattern = /^(?<file>[^:]+):(?<line>\d+):(?<column>\d+): (?<severity>error|warning|note): (?<message>.*)$/
        guard let match = line.wholeMatch(of: pattern) else { return nil }
        guard match.output.severity != "note" else { return nil }
        return Diagnostic(
            line: Int(match.output.line) ?? 0,
            column: Int(match.output.column) ?? 0,
            severity: String(match.output.severity),
            message: String(match.output.message)
        )
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let output = try ToolProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [tool] + arguments
        )
        return output.standardOutput + "\n" + output.standardError
    }
}

/// Parses the `-dump-ast` s-expression format.
///
/// The JSON format would be less work to read, but it concatenates one object
/// per source file with no separator, so it needs incremental decoding anyway —
/// and the s-expression form keeps `decl=` strings intact.
struct SExpressionParser {
    private let characters: [Character]
    private var index = 0

    init(text: String) { characters = Array(text) }

    mutating func parseSourceFiles() throws -> [ASTNode] {
        var files: [ASTNode] = []
        while true {
            skipToNodeStart()
            guard index < characters.count else { break }
            files.append(try parseNode())
        }
        return files
    }

    private mutating func skipToNodeStart() {
        while index < characters.count, characters[index] != "(" { index += 1 }
    }

    private mutating func parseNode() throws -> ASTNode {
        guard consume("(") else { throw SMetalError("AST parse: expected '('") }
        return try parseContents(kind: readToken())
    }

    /// Parses fields and children up to the closing paren. `kind` is already read,
    /// which lets a labelled child like `processed_init=float_literal_expr` reuse this.
    private mutating func parseContents(kind: String) throws -> ASTNode {
        var fields: [String: String] = [:]
        var children: [ASTNode] = []

        while index < characters.count {
            skipWhitespace()
            guard index < characters.count else { break }

            if characters[index] == ")" {
                index += 1
                return ASTNode(kind: kind, fields: fields, children: children)
            }

            if characters[index] == "(" {
                // `(label=node ...)` attaches a labelled child, e.g. processed_init.
                let save = index
                index += 1
                let inner = readToken()
                if let equals = inner.firstIndex(of: "=") {
                    let label = String(inner[inner.startIndex ..< equals])
                    var node = try parseContents(kind: String(inner[inner.index(after: equals)...]))
                    node.fields["label"] = label
                    children.append(node)
                } else {
                    index = save
                    children.append(try parseNode())
                }
                continue
            }

            // A bare `"string"` is the filename of a source_file, or an
            // unlabelled name like the identifier of a struct_decl.
            if characters[index] == "\"" {
                let text = readQuoted()
                if kind == "source_file", fields["filename"] == nil {
                    fields["filename"] = text
                } else if fields["name"] == nil {
                    fields["name"] = text
                }
                continue
            }

            let token = readToken()
            if token.isEmpty { index += 1; continue }
            guard let equals = token.firstIndex(of: "=") else {
                fields[token] = ""
                continue
            }
            let key = String(token[token.startIndex ..< equals])
            var value = String(token[token.index(after: equals)...])
            // Some fields hold a parenthesized list, e.g. `captures=(scale<direct>)`;
            // without this they would parse as a bogus child node.
            if value.isEmpty, index < characters.count, characters[index] == "(" {
                value = readBalancedParens()
            }
            if value.hasPrefix("\"") { value = String(value.dropFirst().dropLast()) }
            fields[key] = value
        }
        throw SMetalError("AST parse: unterminated node '\(kind)'")
    }

    private mutating func readBalancedParens() -> String {
        var result = ""
        var depth = 0
        while index < characters.count {
            let character = characters[index]
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            result.append(character)
            index += 1
            if depth == 0 { break }
        }
        return result
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
    }

    private mutating func consume(_ character: Character) -> Bool {
        skipWhitespace()
        guard index < characters.count, characters[index] == character else { return false }
        index += 1
        return true
    }

    /// Reads one token, keeping `key="quoted value"` and `range=[a - b]` whole.
    private mutating func readToken() -> String {
        skipWhitespace()
        var result = ""
        var quoted = false
        var brackets = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                quoted.toggle()
                result.append(character)
                index += 1
                continue
            }
            if !quoted {
                if character == "[" { brackets += 1 }
                if character == "]" { brackets -= 1 }
                if brackets == 0, character.isWhitespace || character == "(" || character == ")" { break }
            }
            result.append(character)
            index += 1
        }
        if result.hasPrefix("\""), result.hasSuffix("\""), result.count > 1 {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    private mutating func readQuoted() -> String {
        guard consume("\"") else { return "" }
        var result = ""
        while index < characters.count, characters[index] != "\"" {
            result.append(characters[index])
            index += 1
        }
        index += 1
        return result
    }
}
