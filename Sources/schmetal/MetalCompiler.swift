import Foundation

/// Drives `xcrun metal` / `xcrun metallib` over a generated .metal file.
enum MetalCompiler {
    static func compile(metalPath: String, libraryPath: String) throws {
        let airPath = (metalPath as NSString).deletingPathExtension + ".air"
        try run("xcrun", ["-sdk", "macosx", "metal", "-c", metalPath, "-o", airPath])
        try run("xcrun", ["-sdk", "macosx", "metallib", airPath, "-o", libraryPath])
        try? FileManager.default.removeItem(atPath: airPath)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SchmetalError("\(tool) \(arguments.joined(separator: " ")) failed:\n" + String(decoding: output, as: UTF8.self))
        }
    }
}
