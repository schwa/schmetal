import Foundation

struct ToolProcess {
    struct Output {
        let standardOutput: String
        let standardError: String
    }

    static func run(executable: URL, arguments: [String]) throws -> Output {
        let directory = FileManager.default.temporaryDirectory.appending(path: "schmetal-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appending(path: "stdout")
        let errorURL = directory.appending(path: "stderr")
        try Data().write(to: outputURL)
        try Data().write(to: errorURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? errorHandle.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Files cannot fill a pipe buffer while the parent waits for termination.
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        process.waitUntilExit()

        // Preserve diagnostics even when a tool emits invalid UTF-8.
        // swiftlint:disable optional_data_string_conversion
        let output = Output(
            standardOutput: String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
            standardError: String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
        )
        // swiftlint:enable optional_data_string_conversion
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let reason = process.terminationReason == .exit ? "exit status" : "signal"
            let command = ([executable.path] + arguments).joined(separator: " ")
            throw SchmetalError("""
            \(command) failed (\(reason) \(process.terminationStatus)):
            \(output.standardOutput)
            \(output.standardError)
            """)
        }
        return output
    }
}
