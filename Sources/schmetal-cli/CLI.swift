import Foundation
import Schmetal

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
            print(try ShaderCompiler.dumpText(shaderPath: path), terminator: "")

        case "build":
            try build(arguments: rest)

        default:
            usage()
        }
    }

    static func build(arguments: [String]) throws {
        var input: String?
        var output: String?
        var compiler = ShaderCompiler()

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
                compiler.specializations[String(pair[0])] = String(pair[1])
            case "--emit-metal":
                compiler.emitMetalOnly = true
            case let other:
                input = other
            }
            index += 1
        }
        guard let input else { usage() }

        let result = try compiler.compile(
            shaderPath: input, outputs: .generated(for: input, libraryPath: output)
        )
        print("wrote \(result.metalPath)")
        if let libraryPath = result.libraryPath { print("wrote \(libraryPath)") }
    }

}
