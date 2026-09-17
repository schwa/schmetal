import Foundation
import Metal
import Testing
@testable import smetal

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
        let source = try String(contentsOf: root.appending(path: "Examples/\(example).smetal"), encoding: .utf8)
        return try library(source: source, specializations: specializations)
    }

    func library(source: String, specializations: [String: String]) throws -> any MTLLibrary {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smetal-gpu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appending(path: "Shader.smetal")
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
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try #require(library.makeFunction(name: "triangleVertex"))
        descriptor.fragmentFunction = try #require(library.makeFunction(name: "triangleFragment"))
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

    @Test func `canonical types overloads and lexical shadowing execute correctly`() throws {
        let gpu = try GPUHarness()
        let library = try gpu.library(source: """
        import SMetal
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
        import SMetal
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
        import SMetal
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
            import SMetal
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
        let center = (16 * width + 16) * 4
        let expectedCenter: [UInt8] = useUniforms ? [0, 255, 0, 255] : [255, 0, 0, 255]
        #expect(Array(pixels[center..<(center + 4)]) == expectedCenter)
        let side = (16 * width + 20) * 4
        let expectedSide: [UInt8] = useUniforms ? [0, 0, 255, 255] : [255, 0, 0, 255]
        #expect(Array(pixels[side..<(side + 4)]) == expectedSide)
        #expect(Array(pixels[0..<4]) == [0, 0, 255, 255])
    }
}
