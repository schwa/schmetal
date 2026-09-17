import CMSF
import Foundation

struct SMetalError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// Parsed .smetal file: owns the msf result, hands out nodes and token text.
final class SyntaxTree {
    private let result: OpaquePointer
    let source: String
    let path: String

    init(path: String, strict: Bool = true) throws {
        self.path = path
        source = try String(contentsOfFile: path, encoding: .utf8)
        let raw = source.withCString { code in
            path.withCString { name in msf_analyze(code, name) }
        }
        guard let raw else { throw SMetalError("msf_analyze failed for \(path)") }
        result = raw

        let errorCount = msf_error_count(raw)
        if errorCount > 0 {
            let messages = (0 ..< errorCount).map { index -> String in
                let line = msf_error_line(raw, index)
                let text = msf_error_message(raw, index).map { String(cString: $0) } ?? "?"
                return "  \(path):\(line): \(text)"
            }
            let report = "semantic errors:\n" + messages.joined(separator: "\n")
            if strict { throw SMetalError(report) }
            FileHandle.standardError.write(Data("smetal: note: msf reported \(errorCount) unresolved symbols (expected for shader types)\n".utf8))
            _ = report
        }
    }

    deinit { msf_result_free(result) }

    var root: Node {
        Node(raw: msf_root(result)!, tree: self)
    }

    fileprivate var tokens: UnsafePointer<Token> { msf_tokens(result)! }
    fileprivate var src: UnsafePointer<Source> { msf_source(result)! }

    func text(tokenIndex: UInt32) -> String {
        let token = tokens[Int(tokenIndex)]
        let view = msf_token_view(src, withUnsafePointer(to: token) { $0 })
        guard let data = view.data else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: data, count: view.len), as: UTF8.self)
    }
}

struct Node {
    let raw: UnsafePointer<ASTNode>
    let tree: SyntaxTree

    var kind: ASTNodeKind { raw.pointee.kind }
    var kindName: String { String(cString: ast_kind_name(kind)) }

    var children: [Node] {
        var result: [Node] = []
        var child = raw.pointee.first_child
        while let node = child {
            result.append(Node(raw: UnsafePointer(node), tree: tree))
            child = node.pointee.next_sibling
        }
        return result
    }

    func children(of kind: ASTNodeKind) -> [Node] { children.filter { $0.kind == kind } }
    func firstChild(of kind: ASTNodeKind) -> Node? { children.first { $0.kind == kind } }

    /// Full source text spanned by this node's tokens, joined with single spaces.
    var text: String {
        (raw.pointee.tok_idx ..< raw.pointee.tok_end).map { tree.text(tokenIndex: $0) }.joined(separator: " ")
    }

    var firstTokenText: String { tree.text(tokenIndex: raw.pointee.tok_idx) }

    var declName: String { tree.text(tokenIndex: raw.pointee.data.func.name_tok) }
    var varName: String { tree.text(tokenIndex: raw.pointee.data.var.name_tok) }
    var operatorText: String { tree.text(tokenIndex: raw.pointee.data.binary.op_tok) }
    var intValue: Int64 { raw.pointee.data.integer.ival }
    var floatValue: Double { raw.pointee.data.flt.fval }
    var boolValue: Bool { raw.pointee.data.boolean.bval != 0 }
}
