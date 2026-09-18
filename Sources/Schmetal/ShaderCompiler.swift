import Foundation

/// Compiles a `.schmetal` shader to Metal source and a Metal library.
///
/// Owns the whole lifecycle — prelude staging, the Swift frontend, lowering,
/// and the Metal toolchain — so callers only choose inputs and outputs.
public struct ShaderCompiler {
    /// Where generated artifacts are written.
    public struct Outputs {
        public var metalPath: String
        public var libraryPath: String?

        public init(metalPath: String, libraryPath: String? = nil) {
            self.metalPath = metalPath
            self.libraryPath = libraryPath
        }

        /// Writes `<directory>/Generated/<name>.metal` and `.metallib` beside the shader.
        public static func generated(for shaderPath: String, libraryPath: String? = nil) -> Outputs {
            let directory = (shaderPath as NSString).deletingLastPathComponent
            let generated = directory.isEmpty ? "Generated" : directory + "/Generated"
            let name = ((shaderPath as NSString).lastPathComponent as NSString).deletingPathExtension
            return Outputs(
                metalPath: generated + "/" + name + ".metal",
                libraryPath: libraryPath ?? generated + "/" + name + ".metallib"
            )
        }
    }

    /// What a compilation produced.
    public struct Result {
        public let metal: String
        public let metalPath: String
        public let libraryPath: String?
    }

    /// Global constants to replace with literal Metal expressions.
    public var specializations: [String: String]

    /// Stop after writing Metal source.
    public var emitMetalOnly: Bool

    public init(specializations: [String: String] = [:], emitMetalOnly: Bool = false) {
        self.specializations = specializations
        self.emitMetalOnly = emitMetalOnly
    }

    /// Lowers a shader to Metal source without touching the filesystem.
    public func lower(shaderPath: String) throws -> String {
        var emitter = Emitter(ast: try TypedAST(path: shaderPath), specializations: specializations)
        return try emitter.emit()
    }

    @discardableResult
    public func compile(shaderPath: String, outputs: Outputs? = nil) throws -> Result {
        let outputs = outputs ?? Outputs.generated(for: shaderPath)
        let metal = try lower(shaderPath: shaderPath)

        let directory = (outputs.metalPath as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        try metal.write(toFile: outputs.metalPath, atomically: true, encoding: .utf8)
        guard !emitMetalOnly, let libraryPath = outputs.libraryPath else {
            return Result(metal: metal, metalPath: outputs.metalPath, libraryPath: nil)
        }

        let libraryDirectory = (libraryPath as NSString).deletingLastPathComponent
        if !libraryDirectory.isEmpty {
            try FileManager.default.createDirectory(atPath: libraryDirectory, withIntermediateDirectories: true)
        }
        try MetalCompiler.compile(metalPath: outputs.metalPath, libraryPath: libraryPath)
        return Result(metal: metal, metalPath: outputs.metalPath, libraryPath: libraryPath)
    }

    /// Renders the normalized typed AST as indented text.
    public static func dumpText(shaderPath: String) throws -> String {
        try TypedAST(path: shaderPath, strict: false).declarations
            .map { describe(node: $0, indent: 0) }
            .joined()
    }

    private static func describe(node: ASTNode, indent: Int) -> String {
        let details = node.fields
            .filter { ["type", "interface_type", "decl", "value", "name", "result"].contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return String(repeating: "  ", count: indent) + "\(node.kind)  \(details)\n"
            + node.children.map { describe(node: $0, indent: indent + 1) }.joined()
    }
}
