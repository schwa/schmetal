import Foundation

@main
struct CLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("smetal: \(error)\n".utf8))
            exit(1)
        }
    }

    static func usage() -> Never {
        print("""
        smetal — compile .smetal (Swift-flavoured shaders) to .metallib

        usage:
          smetal build <file.smetal> [-o out.metallib] [-D name=value ...] [--emit-metal]
          smetal dump  <file.smetal>
        """)
        exit(1)
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first else { usage() }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "dump":
            guard let path = rest.first else { usage() }
            dump(node: try SyntaxTree(path: path, strict: false).root, indent: 0)

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
                guard pair.count == 2 else { throw SMetalError("bad -D, expected name=value") }
                specializations[String(pair[0])] = String(pair[1])
            case "--emit-metal":
                emitMetalOnly = true
            case let other:
                input = other
            }
            index += 1
        }
        guard let input else { usage() }

        let tree = try SyntaxTree(path: input)
        var emitter = Emitter(tree: tree, specializations: specializations)
        let metal = try emitter.emit()

        let base = (input as NSString).deletingPathExtension
        let metalPath = base + ".metal"
        try metal.write(toFile: metalPath, atomically: true, encoding: .utf8)
        print("wrote \(metalPath)")
        if emitMetalOnly { return }

        let libraryPath = output ?? base + ".metallib"
        try MetalCompiler.compile(metalPath: metalPath, libraryPath: libraryPath)
        print("wrote \(libraryPath)")
    }

    static func dump(node: Node, indent: Int) {
        print(String(repeating: "  ", count: indent) + "\(node.kindName)  «\(node.text.prefix(50))»")
        for child in node.children { dump(node: child, indent: indent + 1) }
    }
}
