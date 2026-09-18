import Foundation

/// Single owner of the supported shader-language contract: which Swift
/// declarations exist in the prelude, and how each lowers to Metal.
///
/// Everything the emitter needs to know about the standard vocabulary comes
/// from here, and `Prelude.source` is generated from the same tables, so a
/// Swift declaration cannot exist without a Metal spelling.
enum ShaderLanguage {
    /// Module name the shader and prelude are compiled under.
    static let moduleName = "SchmetalShader"

    /// Module name shaders `import`, mirroring MSL's `metal_stdlib`.
    static let importName = "MetalStdlib"

    /// `Float4` → `SchmetalShader.Float4`.
    static func qualified(_ name: String) -> String { "\(moduleName).\(name)" }

    // MARK: - Types

    struct VectorType {
        let name: String
        let metal: String
        let element: String
        let components: [String]
        /// Vectors with arithmetic operators and math overloads.
        let arithmetic: Bool
    }

    /// Swift standard library types usable in shaders.
    static let scalarTypes: [String: String] = [
        "Swift.Float": "float", "Swift.Double": "float", "Swift.Int": "int", "Swift.Int32": "int",
        "Swift.UInt": "uint", "Swift.UInt32": "uint", "Swift.Bool": "bool", "Swift.Float16": "half"
    ]

    /// Scalars that can be written as a conversion, e.g. `Int(x)` → `int(x)`.
    static let convertibleScalarTypes: [String: String] = [
        "Swift.Float": "float", "Swift.Int": "int", "Swift.UInt": "uint", "Swift.UInt32": "uint",
        "Swift.Int32": "int", "Swift.Float16": "half"
    ]

    static let vectorTypes: [VectorType] = [
        VectorType(name: "Float2", metal: "float2", element: "Swift.Float", components: ["x", "y"], arithmetic: true),
        VectorType(name: "Float3", metal: "float3", element: "Swift.Float", components: ["x", "y", "z"], arithmetic: true),
        VectorType(name: "Float4", metal: "float4", element: "Swift.Float", components: ["x", "y", "z", "w"], arithmetic: true),
        VectorType(name: "UInt2", metal: "uint2", element: "Swift.UInt32", components: ["x", "y"], arithmetic: false),
        VectorType(name: "UInt3", metal: "uint3", element: "Swift.UInt32", components: ["x", "y", "z"], arithmetic: false)
    ]

    /// Builtin index types and the entry-point attribute each lowers to.
    static let indexTypes: [String: String] = [
        qualified("GridIndex"): "thread_position_in_grid",
        qualified("VertexIndex"): "vertex_id",
        qualified("InstanceIndex"): "instance_id"
    ]

    /// Stage markers and the Metal function qualifier each implies.
    static let stages: [String: String] = [
        qualified("compute"): "kernel", qualified("vertex"): "vertex", qualified("fragment"): "fragment"
    ]

    /// Struct member markers that lower to a fixed Metal attribute.
    /// `@color` is indexed and handled separately by the emitter.
    static let memberAttributes: [String: String] = [
        qualified("position"): "position", qualified("pointSize"): "point_size", qualified("flat"): "flat"
    ]

    /// Index types expose their value as `raw`, which needs no Metal spelling:
    /// the parameter is already a `uint`.
    static let indexRawComponent = "raw"

    static let colorAttribute = qualified("color")

    static let bufferAttribute = qualified("buffer")

    static let bufferType = qualified("Buffer")

    /// Swift type name → Metal spelling, for every type usable as a value.
    static let metalTypes: [String: String] = scalarTypes.merging(
        Dictionary(uniqueKeysWithValues: vectorTypes.map { (qualified($0.name), $0.metal) })
    ) { existing, _ in existing }

    /// Type names usable as `T(...)` conversions or vector constructors.
    static let constructors: [String: String] = convertibleScalarTypes.merging(
        Dictionary(uniqueKeysWithValues: vectorTypes.map { (qualified($0.name), $0.metal) })
    ) { existing, _ in existing }

    /// Vector types whose components may be read directly.
    static let vectorTypeNames: [String] = vectorTypes.map { qualified($0.name) }

    /// Vector types whose operators are declared by the prelude.
    static let arithmeticVectorTypeNames: [String] = vectorTypes.filter(\.arithmetic).map { qualified($0.name) }

    static let componentNames: [String] = ["x", "y", "z", "w"]

    // MARK: - Intrinsics

    struct Intrinsic {
        let name: String
        let metal: String
        /// Number of same-typed arguments.
        let arity: Int
        /// Also available as a Swift standard library function.
        let swiftStandardLibrary: Bool
        /// Declared for vectors as `f(vector, vector, Float)` as well.
        let vectorScalarBlend: Bool
        /// Returns the element type instead of the argument type.
        let reducesToScalar: Bool
        /// Declared once generically over `Comparable` as well as per type.
        let comparable: Bool

        init(
            _ name: String, metal: String? = nil, arity: Int, swiftStandardLibrary: Bool = false,
            vectorScalarBlend: Bool = false, reducesToScalar: Bool = false, comparable: Bool = false
        ) {
            self.name = name
            self.metal = metal ?? name
            self.arity = arity
            self.swiftStandardLibrary = swiftStandardLibrary
            self.vectorScalarBlend = vectorScalarBlend
            self.reducesToScalar = reducesToScalar
            self.comparable = comparable
        }
    }

    static let intrinsics: [Intrinsic] = [
        Intrinsic("sqrt", arity: 1), Intrinsic("sin", arity: 1), Intrinsic("cos", arity: 1),
        Intrinsic("floor", arity: 1), Intrinsic("ceil", arity: 1),
        Intrinsic("abs", arity: 1, swiftStandardLibrary: true),
        Intrinsic("pow", arity: 2),
        Intrinsic("min", arity: 2, swiftStandardLibrary: true, comparable: true),
        Intrinsic("max", arity: 2, swiftStandardLibrary: true, comparable: true),
        Intrinsic("clamp", arity: 3, comparable: true),
        Intrinsic("mix", arity: 3, vectorScalarBlend: true),
        Intrinsic("dot", arity: 2, reducesToScalar: true)
    ]

    static let intrinsicsByName: [String: Intrinsic] =
        Dictionary(uniqueKeysWithValues: intrinsics.map { ($0.name, $0) })

    /// Intrinsics that also resolve to a Swift standard library declaration.
    static let swiftStandardLibraryIntrinsics: [String] =
        intrinsics.filter(\.swiftStandardLibrary).map(\.name)

    // MARK: - Operators

    /// Binary operators that lower to the identically spelled Metal operator.
    static let binaryOperators: [String] = [
        "+", "-", "*", "/", "%", "<", ">", "<=", ">=", "==", "!=",
        "&", "|", "^", "<<", ">>", "&&", "||"
    ]

    static let comparisonOperators: [String] = ["<", ">", "<=", ">=", "==", "!="]

    /// Swift standard library types whose operators are supported.
    static let operatorScalarTypes: [String] =
        ["Float", "Double", "Float16", "Int", "Int32", "UInt", "UInt32", "Bool"].map { "Swift." + $0 }

    // MARK: - Prelude generation

    /// Swift declarations for the vector types and the math vocabulary above.
    static var generatedDeclarations: String {
        (vectorTypes.map(declaration) + [mathDeclarations]).joined(separator: "\n")
    }

    private static func declaration(for vector: VectorType) -> String {
        let fields = vector.components.map { "\($0): \(vector.element)" }.joined(separator: ", ")
        let parameters = vector.components.map { "_ \($0): \(vector.element)" }.joined(separator: ", ")
        let assignments = vector.components.map { "self.\($0) = \($0)" }.joined(separator: "; ")
        var lines = [
            "public struct \(vector.name) {",
            "    public var \(fields)",
            "    public init(\(parameters)) { \(assignments) }"
        ]
        if vector.arithmetic {
            let name = vector.name, element = vector.element
            lines += [
                "    public static func * (lhs: \(name), rhs: \(element)) -> \(name) { lhs }",
                "    public static func * (lhs: \(element), rhs: \(name)) -> \(name) { rhs }",
                "    public static func + (lhs: \(name), rhs: \(name)) -> \(name) { lhs }",
                "    public static func - (lhs: \(name), rhs: \(name)) -> \(name) { lhs }"
            ]
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static var mathDeclarations: String {
        let scalars = ["Swift.Float", "Swift.Double", "Swift.Float16"]
        let vectors = vectorTypes.filter(\.arithmetic)

        var lines = intrinsics.filter(\.comparable).map { intrinsic in
            let parameters = (0..<intrinsic.arity).map { "_ a\($0): T" }.joined(separator: ", ")
            return "public func \(intrinsic.name)<T: Swift.Comparable>(\(parameters)) -> T { a0 }"
        }

        for type in scalars + vectors.map(\.name) {
            let element = vectors.first { $0.name == type }?.element ?? type
            for intrinsic in intrinsics {
                let isVector = vectors.contains { $0.name == type }
                if intrinsic.reducesToScalar && !isVector { continue }
                let parameters = (0..<intrinsic.arity).map { "_ a\($0): \(type)" }.joined(separator: ", ")
                let result = intrinsic.reducesToScalar ? element : type
                let body = intrinsic.reducesToScalar ? "0" : "a0"
                lines.append("public func \(intrinsic.name)(\(parameters)) -> \(result) { \(body) }")
                if isVector && intrinsic.vectorScalarBlend {
                    let blend = (0..<(intrinsic.arity - 1)).map { "_ a\($0): \(type)" }.joined(separator: ", ")
                    lines.append("public func \(intrinsic.name)(\(blend), _ t: \(element)) -> \(type) { a0 }")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
