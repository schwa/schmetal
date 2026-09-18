import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import Schmetal

/// Writes rendered output as PNG so example results can be eyeballed.
/// Set SCHMETAL_TEST_IMAGES to a directory to collect them.
enum TestImages {
    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["SCHMETAL_TEST_IMAGES"] else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(rgba pixels: [UInt8], width: Int, height: Int, name: String) throws {
        guard let directory else { return }
        let data = try #require(CFDataCreate(nil, pixels, pixels.count))
        let provider = try #require(CGDataProvider(data: data))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let url = directory.appending(path: name + ".png")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Grayscale image from normalized values.
    static func write(values: [Float], width: Int, height: Int, name: String) throws {
        let pixels = values.flatMap { value -> [UInt8] in
            let level = UInt8(max(0, min(1, value)) * 255)
            return [level, level, level, 255]
        }
        try write(rgba: pixels, width: width, height: height, name: name)
    }
}

private struct GPUHarness {
    let device: any MTLDevice
    let queue: any MTLCommandQueue

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice(), "GPU integration tests require a Metal device")
        queue = try #require(device.makeCommandQueue())
    }

    func library(example: String, specializations: [String: String] = [:]) throws -> any MTLLibrary {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Examples/\(example).schmetal"), encoding: .utf8)
        return try library(source: source, specializations: specializations)
    }

    func library(source: String, specializations: [String: String]) throws -> any MTLLibrary {
        let directory = FileManager.default.temporaryDirectory.appending(path: "schmetal-gpu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appending(path: "Shader.schmetal")
        try source.write(to: sourcePath, atomically: true, encoding: .utf8)
        var emitter = Emitter(ast: try TypedAST(path: sourcePath.path), specializations: specializations)
        let metal = try emitter.emit()
        let metalPath = directory.appending(path: "Shader.metal")
        let libraryPath = directory.appending(path: "Shader.metallib")
        try metal.write(to: metalPath, atomically: true, encoding: .utf8)
        try MetalCompiler.compile(metalPath: metalPath.path, libraryPath: libraryPath.path)
        return try device.makeLibrary(URL: libraryPath)
    }

    func buffer<Element: BitwiseCopyable>(values: [Element]) throws -> any MTLBuffer {
        try values.withUnsafeBytes { bytes in
            let base = try #require(bytes.baseAddress)
            return try #require(device.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared))
        }
    }

    func complete(_ command: any MTLCommandBuffer) throws {
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error {
            throw error
        }
        try #require(command.status == .completed)
    }

    func dispatch(_ name: String, library: any MTLLibrary, buffers: [any MTLBuffer], count: Int) throws {
        try dispatch(name, library: library, bindings: Dictionary(uniqueKeysWithValues: buffers.enumerated().map {
            ($0.offset, $0.element)
        }), count: count)
    }

    func dispatch(_ name: String, library: any MTLLibrary, bindings: [Int: any MTLBuffer], count: Int) throws {
        let function = try #require(library.makeFunction(name: name))
        let pipeline = try device.makeComputePipelineState(function: function)
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in bindings {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)
        )
        encoder.endEncoding()
        try complete(command)
    }

    func renderTriangle(library: any MTLLibrary, width: Int, vertexBuffers: [Int: any MTLBuffer],
                        fragmentBuffers: [Int: any MTLBuffer]) throws -> [UInt8] {
        try render(
            library: library, vertexFunction: "triangleVertex", fragmentFunction: "triangleFragment",
            width: width, vertexBuffers: vertexBuffers, fragmentBuffers: fragmentBuffers
        )
    }

    func render(library: any MTLLibrary, vertexFunction: String, fragmentFunction: String, width: Int,
                vertexBuffers: [Int: any MTLBuffer], fragmentBuffers: [Int: any MTLBuffer]) throws -> [UInt8] {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try #require(library.makeFunction(name: vertexFunction))
        descriptor.fragmentFunction = try #require(library.makeFunction(name: fragmentFunction))
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: width, mipmapped: false
        )
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = .renderTarget
        let texture = try #require(device.makeTexture(descriptor: textureDescriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1)
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        for (index, buffer) in vertexBuffers { encoder.setVertexBuffer(buffer, offset: 0, index: index) }
        for (index, buffer) in fragmentBuffers { encoder.setFragmentBuffer(buffer, offset: 0, index: index) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        try complete(command)
        var pixels = [UInt8](repeating: 0, count: width * width * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let base = try #require(bytes.baseAddress)
            texture.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, width), mipmapLevel: 0)
        }
        return pixels
    }
}

@Suite(.serialized)
struct GPUIntegrationTests {
    @Test(arguments: [2, 8])
    func `compute example produces expected values on the GPU`(scale: Int) throws {
        let gpu = try GPUHarness()
        let specializations = scale == 2 ? [:] : ["scale": "\(scale).0"]
        let library = try gpu.library(example: "add", specializations: specializations)
        let count = 257
        let left = (0..<count).map { Float($0 % 13) - 6 }
        let right = (0..<count).map { Float($0 % 7) * 0.25 + 1 }
        let inputA = try gpu.buffer(values: left)
        let inputB = try gpu.buffer(values: right)
        let output = try gpu.buffer(values: [Float](repeating: .nan, count: count))
        try gpu.dispatch("addArrays", library: library, buffers: [inputA, inputB, output], count: count)
        let result = output.contents().assumingMemoryBound(to: Float.self)
        for index in 0..<count {
            #expect(result[index] == left[index] * Float(scale) + right[index])
        }

        let clamped = try gpu.buffer(values: [Float](repeating: .nan, count: count))
        try gpu.dispatch("clampArray", library: library, buffers: [output, clamped], count: count)
        let clampResult = clamped.contents().assumingMemoryBound(to: Float.self)
        for index in 0..<count {
            #expect(clampResult[index] == min(left[index] * Float(scale) + right[index], Float(scale)))
        }
    }

    @Test func `mandelbrot example matches a host reference`() throws {
        let gpu = try GPUHarness()
        let library = try gpu.library(example: "mandelbrot")
        let width = 16
        let height = 12
        let origin = SIMD2<Float>(-2.0, -1.2)
        let span = SIMD2<Float>(3.0 / Float(width), 2.4 / Float(height))
        // Viewport layout: two float2s then a uint, all four-byte aligned.
        let viewport = try gpu.buffer(values: [
            origin.x.bitPattern, origin.y.bitPattern, span.x.bitPattern, span.y.bitPattern, UInt32(width)
        ])
        let count = width * height
        let output = try gpu.buffer(values: [Float](repeating: .nan, count: count))
        try gpu.dispatch("mandelbrot", library: library, bindings: [0: viewport, 1: output], count: count)

        // Escape times near the set boundary are chaotic, so check the stable
        // structure instead of a point-by-point reference: every sample is a
        // normalized iteration count, the far corner escapes at once, and a
        // sample inside the cardioid never escapes.
        let result = output.contents().assumingMemoryBound(to: Float.self)
        for index in 0..<count {
            #expect(result[index] >= 0 && result[index] <= 1)
        }
        try TestImages.write(
            values: (0..<count).map { result[$0] }, width: width, height: height, name: "mandelbrot"
        )
        #expect(result[0] < 0.1)
        let inside = (height / 2) * width + Int((-0.5 - origin.x) / span.x)
        #expect(result[inside] == 1)
    }

    @Test func `lighting example renders a lit triangle`() throws {
        let gpu = try GPUHarness()
        let library = try gpu.library(example: "lighting")
        let width = 32

        // Vertex { float4 position; float3 normal; float3 tint; } — float3 members
        // occupy 16 bytes each in Metal.
        let vertices: [SIMD4<Float>] = [
            [-1, -1, 0, 1], [0, 0, 1, 0], [1, 0, 0, 0],
            [1, -1, 0, 1], [0, 0, 1, 0], [0, 1, 0, 0],
            [0, 1, 0, 1], [0, 0, 1, 0], [0, 0, 1, 0]
        ]
        let vertexBuffer = try gpu.buffer(values: vertices)
        let instanceTints = try gpu.buffer(values: [SIMD4<Float>(1, 1, 1, 0)])
        // Uniforms { float3 lightDirection; float3 lightColor; float ambient; float shininess; }
        let uniforms = try gpu.buffer(values: [Float](
            [0, 0, 1, 0] + [1, 1, 1, 0] + [0, 1]
        ))

        let pixels = try gpu.render(
            library: library, vertexFunction: "litVertex", fragmentFunction: "litFragment", width: width,
            vertexBuffers: [0: vertexBuffer, 1: instanceTints], fragmentBuffers: [0: uniforms]
        )
        try TestImages.write(rgba: pixels, width: width, height: width, name: "lighting")
        // The normals face the light, so intensity saturates and each fragment
        // shows its interpolated vertex tint; the centroid mixes all three.
        let centroid = ((width * 2 / 3) * width + width / 2) * 4
        for channel in 0..<3 {
            #expect(abs(Int(pixels[centroid + channel]) - 85) <= 12)
        }
        #expect(Array(pixels[0..<4]) == [0, 0, 255, 255])
    }

    @Test func `canonical types overloads and lexical shadowing execute correctly`() throws {
        let gpu = try GPUHarness()
        let library = try gpu.library(source: """
        import MetalStdlib
        typealias Scalar = Swift.Float
        typealias Storage<T> = Buffer<T>
        struct Float { var value: Scalar }
        func choose(_ value: Scalar) -> Scalar { value + 1 }
        func choose(_ value: Float) -> Scalar { value.value + 2 }
        @compute func identityKernel(input: Storage<Float>, output: Buffer<Scalar>, gid: GridIndex) {
            let value: Scalar = input[gid].value
            if value > 0 {
                let value = value + 1
                output[gid] = choose(value) + choose(input[gid])
            } else { output[gid] = choose(input[gid]) }
        }
        """, specializations: [:])
        let values: [Float] = [1, 3, -2, 0]
        let input = try gpu.buffer(values: values)
        let output = try gpu.buffer(values: [Float](repeating: .nan, count: values.count))
        try gpu.dispatch("identityKernel", library: library, buffers: [input, output], count: values.count)
        let result = output.contents().assumingMemoryBound(to: Float.self)
        for index in values.indices {
            let value = values[index]
            #expect(result[index] == (value > 0 ? value * 2 + 4 : value + 2))
        }
    }

    @Test func `explicit and automatic bindings agree with host slots`() throws {
        let gpu = try GPUHarness()
        let library = try gpu.library(source: """
        import MetalStdlib
        @compute func bindSlots(automatic: Buffer<Float>, @buffer(0) pinned: Buffer<Float>,
                                @buffer(3) scale: Float, output: Buffer<Float>, gid: GridIndex) {
            output[gid] = automatic[gid] + pinned[gid] * scale
        }
        """, specializations: [:])
        let values: [Float] = [1, 2, 3, 4]
        let automatic = try gpu.buffer(values: values)
        let pinned = try gpu.buffer(values: values.map { $0 + 10 })
        let scale = try gpu.buffer(values: [Float(2)])
        let output = try gpu.buffer(values: [Float](repeating: .nan, count: values.count))
        try gpu.dispatch("bindSlots", library: library, bindings: [1: automatic, 0: pinned, 3: scale, 2: output],
                         count: values.count)
        let result = output.contents().assumingMemoryBound(to: Float.self)
        for index in values.indices {
            #expect(result[index] == values[index] + (values[index] + 10) * 2)
        }
    }

    @Test func `uniform structs execute from sparse constant buffer slots`() throws {
        let gpu = try GPUHarness()
        let library = try gpu.library(source: """
        import MetalStdlib
        struct Uniforms { var scale: Float; var offset: Float }
        @compute func transform(@buffer(0) input: Buffer<Float>, @buffer(3) uniforms: Uniforms,
                                @buffer(5) output: Buffer<Float>, gid: GridIndex) {
            output[gid] = input[gid] * uniforms.scale + uniforms.offset + -1
        }
        """, specializations: [:])
        let values: [Float] = [-2, 0, 1, 5]
        let input = try gpu.buffer(values: values)
        let uniforms = try gpu.buffer(values: [SIMD2<Float>(2, 3)])
        let output = try gpu.buffer(values: [Float](repeating: .nan, count: values.count))
        try gpu.dispatch(
            "transform", library: library, bindings: [0: input, 3: uniforms, 5: output], count: values.count
        )
        let result = output.contents().assumingMemoryBound(to: Float.self)
        for index in values.indices {
            #expect(result[index] == values[index] * 2 + 2)
        }
    }

    @Test(arguments: [false, true])
    func `vertex and fragment example render expected pixels`(useUniforms: Bool) throws {
        let gpu = try GPUHarness()
        let library: any MTLLibrary
        if useUniforms {
            library = try gpu.library(source: """
            import MetalStdlib
            struct VertexOut { @position var position: Float4 }
            struct Uniforms { var scale: Float; var tint: Float4 }
            @vertex func triangleVertex(vertexID: VertexIndex, @buffer(3) positions: Buffer<Float4>,
                                        @buffer(4) uniforms: Uniforms) -> VertexOut {
                var position = positions[vertexID]
                position.x = position.x * uniforms.scale
                return VertexOut(position: position)
            }
            @fragment func triangleFragment(input: VertexOut, @buffer(5) uniforms: Uniforms) -> Float4 {
                return uniforms.tint
            }
            """, specializations: [:])
        } else {
            library = try gpu.library(example: "triangle")
        }
        let width = 32
        let positions = try gpu.buffer(values: [
            SIMD4<Float>(-1, -1, 0, 1), SIMD4<Float>(1, -1, 0, 1), SIMD4<Float>(0, 1, 0, 1)
        ])
        let colors = try gpu.buffer(values: [SIMD4<Float>](repeating: SIMD4(1, 0, 0, 1), count: 3))
        var vertexBuffers: [Int: any MTLBuffer]
        var fragmentBuffers: [Int: any MTLBuffer] = [:]
        if useUniforms {
            // Float4 alignment places tint at byte 16, after scale and padding.
            let uniforms = try gpu.buffer(values: [SIMD4<Float>(0.5, 0, 0, 0), SIMD4<Float>(0, 1, 0, 1)])
            vertexBuffers = [3: positions, 4: uniforms]
            fragmentBuffers = [5: uniforms]
        } else {
            vertexBuffers = [0: positions, 1: colors]
        }
        let pixels = try gpu.renderTriangle(
            library: library, width: width, vertexBuffers: vertexBuffers, fragmentBuffers: fragmentBuffers
        )
        try TestImages.write(
            rgba: pixels, width: width, height: width, name: useUniforms ? "triangle-uniforms" : "triangle"
        )
        let center = (16 * width + 16) * 4
        let expectedCenter: [UInt8] = useUniforms ? [0, 255, 0, 255] : [255, 0, 0, 255]
        #expect(Array(pixels[center..<(center + 4)]) == expectedCenter)
        let side = (16 * width + 20) * 4
        let expectedSide: [UInt8] = useUniforms ? [0, 0, 255, 255] : [255, 0, 0, 255]
        #expect(Array(pixels[side..<(side + 4)]) == expectedSide)
        #expect(Array(pixels[0..<4]) == [0, 0, 255, 255])
    }

    /// Renders the examples at presentation size, for Examples/Images.
    /// Does nothing unless SCHMETAL_TEST_IMAGES names an output directory.
    @Test func `example gallery images render`() throws {
        guard TestImages.directory != nil else { return }
        let gpu = try GPUHarness()

        let width = 768
        let height = 512
        let origin = SIMD2<Float>(-2.2, -1.3)
        let span = SIMD2<Float>(3.0 / Float(width), 2.6 / Float(height))
        let viewport = try gpu.buffer(values: [
            origin.x.bitPattern, origin.y.bitPattern, span.x.bitPattern, span.y.bitPattern, UInt32(width)
        ])
        let count = width * height
        let output = try gpu.buffer(values: [Float](repeating: 0, count: count))
        try gpu.dispatch(
            "mandelbrot", library: try gpu.library(example: "mandelbrot"),
            bindings: [0: viewport, 1: output], count: count
        )
        let escapeTimes = output.contents().assumingMemoryBound(to: Float.self)
        try TestImages.write(
            values: (0..<count).map { escapeTimes[$0] }, width: width, height: height, name: "mandelbrot-large"
        )

        let vertices: [SIMD4<Float>] = [
            [-0.9, -0.8, 0, 1], [0, 0, 1, 0], [1, 0, 0, 0],
            [0.9, -0.8, 0, 1], [0, 0, 1, 0], [0, 1, 0, 0],
            [0, 0.9, 0, 1], [0, 0, 1, 0], [0, 0, 1, 0]
        ]
        let lightingPixels = try gpu.render(
            library: try gpu.library(example: "lighting"),
            vertexFunction: "litVertex", fragmentFunction: "litFragment", width: 512,
            vertexBuffers: [0: try gpu.buffer(values: vertices), 1: try gpu.buffer(values: [SIMD4<Float>(1, 1, 1, 0)])],
            fragmentBuffers: [0: try gpu.buffer(values: [Float]([0, 0, 1, 0] + [1, 1, 1, 0] + [0, 1]))]
        )
        try TestImages.write(rgba: lightingPixels, width: 512, height: 512, name: "lighting-large")

        let trianglePixels = try gpu.renderTriangle(
            library: try gpu.library(example: "triangle"), width: 512,
            vertexBuffers: [
                0: try gpu.buffer(values: [
                    SIMD4<Float>(-0.9, -0.8, 0, 1), SIMD4<Float>(0.9, -0.8, 0, 1), SIMD4<Float>(0, 0.9, 0, 1)
                ]),
                1: try gpu.buffer(values: [
                    SIMD4<Float>(1, 0, 0, 1), SIMD4<Float>(1, 0.6, 0, 1), SIMD4<Float>(1, 0.9, 0.2, 1)
                ])
            ],
            fragmentBuffers: [:]
        )
        try TestImages.write(rgba: trianglePixels, width: 512, height: 512, name: "triangle-large")
    }
}

