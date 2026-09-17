import Foundation

enum Prelude {
    static let moduleName = "SMetal"

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
    public struct Float2 {
        public var x: Swift.Float, y: Swift.Float
        public init(_ x: Swift.Float, _ y: Swift.Float) { self.x = x; self.y = y }
        public static func * (lhs: Float2, rhs: Swift.Float) -> Float2 { lhs }
        public static func * (lhs: Swift.Float, rhs: Float2) -> Float2 { rhs }
        public static func + (lhs: Float2, rhs: Float2) -> Float2 { lhs }
        public static func - (lhs: Float2, rhs: Float2) -> Float2 { lhs }
    }
    public struct Float3 {
        public var x: Swift.Float, y: Swift.Float, z: Swift.Float
        public init(_ x: Swift.Float, _ y: Swift.Float, _ z: Swift.Float) { self.x = x; self.y = y; self.z = z }
        public static func * (lhs: Float3, rhs: Swift.Float) -> Float3 { lhs }
        public static func * (lhs: Swift.Float, rhs: Float3) -> Float3 { rhs }
        public static func + (lhs: Float3, rhs: Float3) -> Float3 { lhs }
        public static func - (lhs: Float3, rhs: Float3) -> Float3 { lhs }
    }
    public struct Float4 {
        public var x: Swift.Float, y: Swift.Float, z: Swift.Float, w: Swift.Float
        public init(_ x: Swift.Float, _ y: Swift.Float, _ z: Swift.Float, _ w: Swift.Float) {
            self.x = x; self.y = y; self.z = z; self.w = w
        }
        public static func * (lhs: Float4, rhs: Swift.Float) -> Float4 { lhs }
        public static func * (lhs: Swift.Float, rhs: Float4) -> Float4 { rhs }
        public static func + (lhs: Float4, rhs: Float4) -> Float4 { lhs }
        public static func - (lhs: Float4, rhs: Float4) -> Float4 { lhs }
    }
    public struct UInt2 {
        public var x: Swift.UInt32, y: Swift.UInt32
        public init(_ x: Swift.UInt32, _ y: Swift.UInt32) { self.x = x; self.y = y }
    }
    public struct UInt3 {
        public var x: Swift.UInt32, y: Swift.UInt32, z: Swift.UInt32
        public init(_ x: Swift.UInt32, _ y: Swift.UInt32, _ z: Swift.UInt32) { self.x = x; self.y = y; self.z = z }
    }
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
    public func min<T: Swift.Comparable>(_ a: T, _ b: T) -> T { a }
    public func max<T: Swift.Comparable>(_ a: T, _ b: T) -> T { a }
    public func clamp<T: Swift.Comparable>(_ x: T, _ low: T, _ high: T) -> T { x }
    """# + "\n" + mathDeclarations

    private static var mathDeclarations: String {
        let scalarTypes = ["Swift.Float", "Swift.Double", "Swift.Float16"]
        let vectorTypes = ["Float2", "Float3", "Float4"]
        return (scalarTypes + vectorTypes).flatMap { type -> [String] in
            var declarations = [String]()
            for name in ["sqrt", "sin", "cos", "floor", "ceil", "abs"] {
                declarations.append("public func \(name)(_ value: \(type)) -> \(type) { value }")
            }
            for name in ["pow", "min", "max"] {
                declarations.append("public func \(name)(_ a: \(type), _ b: \(type)) -> \(type) { a }")
            }
            for name in ["clamp", "mix"] {
                declarations.append("public func \(name)(_ a: \(type), _ b: \(type), _ c: \(type)) -> \(type) { a }")
            }
            if vectorTypes.contains(type) {
                declarations.append("public func mix(_ a: \(type), _ b: \(type), _ t: Swift.Float) -> \(type) { a }")
                declarations.append("public func dot(_ a: \(type), _ b: \(type)) -> Swift.Float { 0 }")
            }
            return declarations
        }.joined(separator: "\n")
    }

    static func stage(shaderPath: String) throws -> (directory: URL, prelude: URL, shader: URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smetal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let prelude = directory.appending(path: "SMetalPrelude.swift")
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
