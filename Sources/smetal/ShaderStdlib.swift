// msf reads these declarations as a vocabulary; Metal lowering remains name-based.
enum ShaderStdlib {
    static let moduleName = "SMetal"

    static let source = """
    public struct Float2 { public init(_ x: Float, _ y: Float) }
    public struct Float3 { public init(_ x: Float, _ y: Float, _ z: Float) }
    public struct Float4 {
        public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float)
        public var x: Float
        public var y: Float
        public var z: Float
        public var w: Float
    }
    public struct UInt2 { public init(_ x: UInt32, _ y: UInt32) }
    public struct UInt3 { public init(_ x: UInt32, _ y: UInt32, _ z: UInt32) }
    public struct Half {}

    /// A `device` pointer to `Element`, bound to a buffer argument.
    public struct Buffer<Element> {
        public subscript(index: UInt32) -> Element
    }

    /// `[[thread_position_in_grid]]`
    public struct GridIndex {}
    /// `[[vertex_id]]`
    public struct VertexIndex {}
    /// `[[instance_id]]`
    public struct InstanceIndex {}
    """
}
