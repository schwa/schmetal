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
        let directory = FileManager.default.temporaryDirectory.appending(path: "smetal-gpu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appending(path: example + ".smetal")
        let source = try String(contentsOf: root.appending(path: "Examples/\(example).smetal"), encoding: .utf8)
        try source.write(to: sourcePath, atomically: true, encoding: .utf8)
        var emitter = Emitter(ast: try TypedAST(path: sourcePath.path), specializations: specializations)
        let metal = try emitter.emit()
        let metalPath = directory.appending(path: example + ".metal")
        let libraryPath = directory.appending(path: example + ".metallib")
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
        let function = try #require(library.makeFunction(name: name))
        let pipeline = try device.makeComputePipelineState(function: function)
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in buffers.enumerated() {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)
        )
        encoder.endEncoding()
        try complete(command)
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

    @Test func `vertex and fragment example render expected pixels`() throws {
        let gpu = try GPUHarness()
        let library = try gpu.library(example: "triangle")
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try #require(library.makeFunction(name: "triangleVertex"))
        descriptor.fragmentFunction = try #require(library.makeFunction(name: "triangleFragment"))
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try gpu.device.makeRenderPipelineState(descriptor: descriptor)

        let width = 32
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: width, mipmapped: false
        )
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = .renderTarget
        let texture = try #require(gpu.device.makeTexture(descriptor: textureDescriptor))
        let positions = try gpu.buffer(values: [
            SIMD4<Float>(-1, -1, 0, 1), SIMD4<Float>(1, -1, 0, 1), SIMD4<Float>(0, 1, 0, 1)
        ])
        let colors = try gpu.buffer(values: [SIMD4<Float>](repeating: SIMD4(1, 0, 0, 1), count: 3))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1)
        let command = try #require(gpu.queue.makeCommandBuffer())
        let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(positions, offset: 0, index: 0)
        encoder.setVertexBuffer(colors, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        try gpu.complete(command)

        var pixels = [UInt8](repeating: 0, count: width * width * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let base = try #require(bytes.baseAddress)
            texture.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, width), mipmapLevel: 0)
        }
        let center = (16 * width + 16) * 4
        #expect(Array(pixels[center..<(center + 4)]) == [255, 0, 0, 255])
        #expect(Array(pixels[0..<4]) == [0, 0, 255, 255])
    }
}
