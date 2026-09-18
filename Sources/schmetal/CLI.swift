import Foundation

@main
struct CLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("schmetal: \(error)\n".utf8))
            exit(1)
        }
    }

    static func usage() -> Never {
        print("""
        schmetal — compile .schmetal (Swift-flavoured shaders) to .metallib

        usage:
          schmetal build <file.schmetal> [-o out.metallib] [-D name=value ...] [--emit-metal]
          schmetal dump  <file.schmetal>
        """)
        exit(1)
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first else { usage() }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "dump":
            guard let path = rest.first else { usage() }
            for declaration in try TypedAST(path: path, strict: false).declarations {
                dump(node: declaration, indent: 0)
            }

        case "build":
            try build(arguments: rest)

        default:
            usage()
        }
    }

    static func build(arguments: [String]) throws {
        var input: String?
        var output: String?
        var specializations: [String: String] = [:]
        var emitMetalOnly = false

        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "-o":
                index += 1
                output = arguments[index]
            case "-D":
                index += 1
                let pair = arguments[index].split(separator: "=", maxSplits: 1)
                guard pair.count == 2 else { throw SchmetalError("bad -D, expected name=value") }
                specializations[String(pair[0])] = String(pair[1])
            case "--emit-metal":
                emitMetalOnly = true
            case let other:
                input = other
            }
            index += 1
        }
        guard let input else { usage() }

        let ast = try TypedAST(path: input)
        var emitter = Emitter(ast: ast, specializations: specializations)
        let metal = try emitter.emit()

        // Generated Metal and libraries land in a Generated/ subdirectory beside
        // the shader so the source directory stays readable.
        let directory = (input as NSString).deletingLastPathComponent
        let generated = (directory.isEmpty ? "Generated" : directory + "/Generated")
        try FileManager.default.createDirectory(atPath: generated, withIntermediateDirectories: true)
        let name = ((input as NSString).lastPathComponent as NSString).deletingPathExtension
        let base = generated + "/" + name
        let metalPath = base + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        print("wrote \(metalPath)")
        if emitMetalOnly { return }

        let libraryPath = output ?? base + ".metallib"
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: libraryPath)
        print("wrote \(libraryPath)")
    }

    static func dump(node: ASTNode, indent: Int) {
        let details = node.fields
            .filter { ["type", "interface_type", "decl", "value", "name", "result"].contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print(String(repeating: "  ", count: indent) + "\(node.kind)  \(details)")
        for child in node.children { dump(node: child, indent: indent + 1) }
    }
}
