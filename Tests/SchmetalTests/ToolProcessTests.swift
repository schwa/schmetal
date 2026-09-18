import Foundation
import Testing
@testable import schmetal

@Test func `large output on both streams completes without pipe backpressure`() throws {
    let output = try ToolProcess.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", """
        /bin/dd if=/dev/zero bs=1048576 count=2 2>/dev/null
        (/bin/dd if=/dev/zero bs=1048576 count=2 2>/dev/null) >&2
        """]
    )
    #expect(output.standardOutput.utf8.count == 2 * 1_048_576)
    #expect(output.standardError.utf8.count == 2 * 1_048_576)
}

@Test func `nonzero exit preserves both output streams and status`() throws {
    do {
        _ = try ToolProcess.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf partial-AST; printf 'driver failure without source location' >&2; exit 7"]
        )
        Issue.record("Accepted a nonzero exit")
    } catch let error as SchmetalError {
        #expect(error.description.contains("exit status 7"))
        #expect(error.description.contains("partial-AST"))
        #expect(error.description.contains("driver failure without source location"))
    }
}

@Test func `signal termination is a failure`() throws {
    do {
        _ = try ToolProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "kill -TERM $$"])
        Issue.record("Accepted signal termination")
    } catch let error as SchmetalError {
        #expect(error.description.contains("signal 15"))
    }
}

@Test func `missing executable throws`() throws {
    #expect(throws: (any Error).self) {
        try ToolProcess.run(executable: URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString)"), arguments: [])
    }
}
