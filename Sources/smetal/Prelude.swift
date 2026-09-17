import Foundation

/// The real Swift module a .smetal file imports. swiftc type-checks against this,
/// then we lower the resulting typed AST to MSL. Bodies exist only to keep the
/// optimizer and diagnostics happy — none of this code ever runs.
enum Prelude {
    static let moduleName = "SMetal"

    static let source = #"""
    // Entry-point stages. Global actors are the only user-definable function
    // attribute in Swift that needs no macro plugin; we read them back as
    // `custom_attr type="compute"` and never actually isolate anything.
    @globalActor public actor compute { public static let shared = compute() }
    @globalActor public actor vertex { public static let shared = vertex() }
    @globalActor public actor fragment { public static let shared = fragment() }

    // Struct member attributes. A property wrapper leaves `var_decl
    // interface_type` as the unwrapped type, so lowering reads the declared type.
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

    public typealias Half = Float16

    public struct Float2 {
        public var x: Float, y: Float
        public init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
        public static func * (lhs: Float2, rhs: Float) -> Float2 { lhs }
        public static func * (lhs: Float, rhs: Float2) -> Float2 { rhs }
        public static func + (lhs: Float2, rhs: Float2) -> Float2 { lhs }
        public static func - (lhs: Float2, rhs: Float2) -> Float2 { lhs }
    }

    public struct Float3 {
        public var x: Float, y: Float, z: Float
        public init(_ x: Float, _ y: Float, _ z: Float) { self.x = x; self.y = y; self.z = z }
        public static func * (lhs: Float3, rhs: Float) -> Float3 { lhs }
        public static func * (lhs: Float, rhs: Float3) -> Float3 { rhs }
        public static func + (lhs: Float3, rhs: Float3) -> Float3 { lhs }
        public static func - (lhs: Float3, rhs: Float3) -> Float3 { lhs }
    }

    public struct Float4 {
        public var x: Float, y: Float, z: Float, w: Float
        public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
            self.x = x; self.y = y; self.z = z; self.w = w
        }
        public static func * (lhs: Float4, rhs: Float) -> Float4 { lhs }
        public static func * (lhs: Float, rhs: Float4) -> Float4 { rhs }
        public static func + (lhs: Float4, rhs: Float4) -> Float4 { lhs }
        public static func - (lhs: Float4, rhs: Float4) -> Float4 { lhs }
    }

    public struct UInt2 {
        public var x: UInt32, y: UInt32
        public init(_ x: UInt32, _ y: UInt32) { self.x = x; self.y = y }
    }

    public struct UInt3 {
        public var x: UInt32, y: UInt32, z: UInt32
        public init(_ x: UInt32, _ y: UInt32, _ z: UInt32) { self.x = x; self.y = y; self.z = z }
    }

    /// A `device` pointer bound to a buffer argument.
    public struct Buffer<Element> {
        public var base: UnsafeMutablePointer<Element>
        public subscript(index: UInt32) -> Element {
            get { base[Int(index)] }
            nonmutating set { base[Int(index)] = newValue }
        }
        public subscript(index: Int) -> Element {
            get { base[index] }
            nonmutating set { base[index] = newValue }
        }
        public subscript(index: GridIndex) -> Element {
            get { base[Int(index.raw)] }
            nonmutating set { base[Int(index.raw)] = newValue }
        }
        public subscript(index: VertexIndex) -> Element {
            get { base[Int(index.raw)] }
            nonmutating set { base[Int(index.raw)] = newValue }
        }
        public subscript(index: InstanceIndex) -> Element {
            get { base[Int(index.raw)] }
            nonmutating set { base[Int(index.raw)] = newValue }
        }
    }

    /// `[[thread_position_in_grid]]`
    public struct GridIndex { public var raw: UInt32 }
    /// `[[vertex_id]]`
    public struct VertexIndex { public var raw: UInt32 }
    /// `[[instance_id]]`
    public struct InstanceIndex { public var raw: UInt32 }

    public func min<T: Comparable>(_ a: T, _ b: T) -> T { a }
    public func max<T: Comparable>(_ a: T, _ b: T) -> T { a }
    public func clamp<T: Comparable>(_ x: T, _ low: T, _ high: T) -> T { x }
    """# + "\n" + mathDeclarations

    private static var mathDeclarations: String {
        let scalarTypes = ["Float", "Double", "Half"]
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
                declarations.append("public func mix(_ a: \(type), _ b: \(type), _ t: Float) -> \(type) { a }")
                declarations.append("public func dot(_ a: \(type), _ b: \(type)) -> Float { 0 }")
            }
            return declarations
        }.joined(separator: "\n")
    }

    /// Writes the prelude next to a copy of the shader so swiftc sees both files.
    /// `import SMetal` is stripped: the prelude is compiled into the same module.
    static func stage(shaderPath: String) throws -> (directory: URL, prelude: URL, shader: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "smetal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let prelude = directory.appending(path: "SMetalPrelude.swift")
        try source.write(to: prelude, atomically: true, encoding: .utf8)

        let name = (shaderPath as NSString).lastPathComponent
        let shader = directory.appending(path: (name as NSString).deletingPathExtension + ".swift")
        let original = try String(contentsOfFile: shaderPath, encoding: .utf8)
        try stripImport(original).write(to: shader, atomically: true, encoding: .utf8)

        return (directory, prelude, shader)
    }

    /// Replaces `import SMetal` with a blank line, preserving line numbers so
    /// swiftc diagnostics still point at the right line of the .smetal file.
    static func stripImport(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) == "import \(moduleName)" ? "" : String($0) }
            .joined(separator: "\n")
    }
}
