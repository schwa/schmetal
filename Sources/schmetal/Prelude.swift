import Foundation

enum Prelude {
    static let moduleName = ShaderLanguage.importName

    static let source = #"""
    // Global actors encode stages without macros, but impose Swift isolation checks.
    @globalActor public actor compute { public static let shared = compute() }
    @globalActor public actor vertex { public static let shared = vertex() }
    @globalActor public actor fragment { public static let shared = fragment() }

    @propertyWrapper public struct position<T> {
        public var wrappedValue: T
        public init(wrappedValue: T) { self.wrappedValue = wrappedValue }
    }
    @propertyWrapper public struct pointSize<T> {
        public var wrappedValue: T
        public init(wrappedValue: T) { self.wrappedValue = wrappedValue }
    }
    @propertyWrapper public struct flat<T> {
        public var wrappedValue: T
        public init(wrappedValue: T) { self.wrappedValue = wrappedValue }
    }
    @propertyWrapper public struct color<T> {
        public var wrappedValue: T
        public init(wrappedValue: T) { self.wrappedValue = wrappedValue }
    }

    @propertyWrapper public struct buffer<Value> {
        public let wrappedValue: Value
        public init(wrappedValue: Value, _ index: Swift.Int) { self.wrappedValue = wrappedValue }
    }

    public typealias Half = Swift.Float16
    public struct Buffer<Element> {
        public var base: Swift.UnsafeMutablePointer<Element>
        public subscript(index: Swift.UInt32) -> Element {
            get { base[Swift.Int(index)] }
            nonmutating set { base[Swift.Int(index)] = newValue }
        }
        public subscript(index: Swift.Int) -> Element {
            get { base[index] }
            nonmutating set { base[index] = newValue }
        }
        public subscript(index: GridIndex) -> Element {
            get { base[Swift.Int(index.raw)] }
            nonmutating set { base[Swift.Int(index.raw)] = newValue }
        }
        public subscript(index: VertexIndex) -> Element {
            get { base[Swift.Int(index.raw)] }
            nonmutating set { base[Swift.Int(index.raw)] = newValue }
        }
        public subscript(index: InstanceIndex) -> Element {
            get { base[Swift.Int(index.raw)] }
            nonmutating set { base[Swift.Int(index.raw)] = newValue }
        }
    }
    public struct GridIndex { public var raw: Swift.UInt32 }
    public struct VertexIndex { public var raw: Swift.UInt32 }
    public struct InstanceIndex { public var raw: Swift.UInt32 }
    """# + "\n" + ShaderLanguage.generatedDeclarations

    static func stage(shaderPath: String) throws -> (directory: URL, prelude: URL, shader: URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "schmetal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let prelude = directory.appending(path: "SchmetalPrelude.swift")
            try source.write(to: prelude, atomically: true, encoding: .utf8)
            let shader = directory.appending(path: "Shader.swift")
            let original = try String(contentsOfFile: shaderPath, encoding: .utf8)
            try stripImport(original).write(to: shader, atomically: true, encoding: .utf8)
            return (directory, prelude, shader)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func stripImport(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.trimmingCharacters(in: .whitespaces) == "import \(moduleName)"
                ? String(repeating: " ", count: line.utf8.count) : String(line)
        }.joined(separator: "\n")
    }
}
