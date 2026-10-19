// Run from the repository root:
// swiftc MacStat/MacStat/LidSleepController.swift Tests/LidSleepControllerTests.swift -o /tmp/macstat-lid-tests
// /tmp/macstat-lid-tests
// All kernel writes are replaced by a recorder; these tests do not change sleep policy.
import Foundation
import Darwin

private final class HelperSession {
    let pipe = Pipe()
    private let condition = NSCondition()
    private var events: [Bool] = []
    private var result: Int32?

    init(failAt: Int? = nil) {
        DispatchQueue.global().async { [self] in
            let status = LidSleepController.runHelper(input: pipe.fileHandleForReading) { disabled in
                self.condition.lock()
                defer { self.condition.unlock() }
                self.events.append(disabled)
                self.condition.broadcast()
                return self.events.count != failAt
            }
            condition.lock()
            result = status
            condition.broadcast()
            condition.unlock()
        }
    }

    func send(_ commands: [UInt8]) throws {
        try pipe.fileHandleForWriting.write(contentsOf: Data(commands))
    }

    func waitForEvents(_ count: Int) -> [Bool] {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(4)
        while events.count < count && result == nil {
            precondition(condition.wait(until: deadline), "Timed out waiting for helper commands")
        }
        precondition(events.count >= count)
        return events
    }

    func finish() throws -> (Int32, [Bool]) {
        try pipe.fileHandleForWriting.close()
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(4)
        while result == nil {
            precondition(condition.wait(until: deadline), "Helper did not exit after EOF")
        }
        return (result!, events)
    }
}

@main
enum LidSleepControllerTests {
    static func main() throws {
        // The real Process / Pipe controller talks to this recording helper.
        if CommandLine.arguments.dropFirst() == [LidSleepController.helperArgument] {
            let path = ProcessInfo.processInfo.environment["MACSTAT_LID_TEST_LOG"]!
            let log = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            exit(LidSleepController.runHelper(input: .standardInput) { disabled in
                _ = try? log.seekToEnd()
                try? log.write(contentsOf: Data((disabled ? "1\n" : "0\n").utf8))
                if ProcessInfo.processInfo.environment["MACSTAT_LID_TEST_CRASH_HELPER"] == "1" {
                    kill(getpid(), SIGKILL)
                }
                return true
            })
        }
        if CommandLine.arguments.dropFirst() == ["--simulate-parent-crash"] {
            let controller = LidSleepController(restoreSleep: {})
            try controller.setEnabled(true)
            waitForLog(["1"])
            // Skip Swift deinit, just as a force-quit would.
            _exit(0)
        }

        let idle = HelperSession()
        let idleResult = try idle.finish()
        precondition(idleResult.0 == 0 && idleResult.1.isEmpty,
                     "An unused helper must leave other sleep policy alone")

        let toggled = HelperSession()
        try toggled.send([1])
        _ = toggled.waitForEvents(2) // Includes a heartbeat after one second.
        try toggled.send([0])
        precondition(toggled.waitForEvents(3).last == false)
        try toggled.send([1])
        precondition(toggled.waitForEvents(4).last == true)
        let toggledResult = try toggled.finish()
        precondition(toggledResult.0 == 0 && toggledResult.1.last == false,
                     "EOF while enabled must restore lid sleep")

        let disabled = HelperSession()
        try disabled.send([1])
        _ = disabled.waitForEvents(1)
        try disabled.send([0])
        _ = disabled.waitForEvents(2)
        let disabledResult = try disabled.finish()
        precondition(disabledResult.0 == 0 && disabledResult.1 == [true, false],
                     "Exiting after disable must not clear the global flag again")

        let rejected = HelperSession(failAt: 1)
        try rejected.send([1])
        let rejectedResult = try rejected.finish()
        precondition(rejectedResult.0 == 1 && rejectedResult.1 == [true])

        let heartbeatFailure = HelperSession(failAt: 2)
        try heartbeatFailure.send([1])
        _ = heartbeatFailure.waitForEvents(3)
        let heartbeatResult = try heartbeatFailure.finish()
        precondition(heartbeatResult.0 == 1 && heartbeatResult.1 == [true, true, false],
                     "A failed reapply must attempt cleanup")

        let disableFailure = HelperSession(failAt: 2)
        try disableFailure.send([1])
        _ = disableFailure.waitForEvents(1)
        try disableFailure.send([0])
        let failureResult = try disableFailure.finish()
        precondition(failureResult.0 == 1 && failureResult.1 == [true, false, false],
                     "A failed disable must retry during cleanup")

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macstat-lid-test-\(UUID().uuidString)")
        try Data().write(to: logURL)
        setenv("MACSTAT_LID_TEST_LOG", logURL.path, 1)
        defer {
            unsetenv("MACSTAT_LID_TEST_LOG")
            try? FileManager.default.removeItem(at: logURL)
        }
        let controller = LidSleepController(restoreSleep: {})
        try controller.setEnabled(true)
        waitForLog(["1"])
        try controller.setEnabled(true)
        waitForLog(["1", "1"], timeout: 0.5)
        try controller.setEnabled(false)
        waitForLog(["1", "1", "0"])
        try controller.setEnabled(true)
        waitForLog(["1", "1", "0", "1"])
        controller.stop()
        waitForLog(["1", "1", "0", "1", "0"])

        try Data().write(to: logURL)
        let parent = Process()
        parent.executableURL = Bundle.main.executableURL
        parent.arguments = ["--simulate-parent-crash"]
        try parent.run()
        parent.waitUntilExit()
        precondition(parent.terminationStatus == 0)
        waitForLog(["1", "0"])

        var restoredAfterHelperCrash = false
        var reportedHelperCrash = false
        setenv("MACSTAT_LID_TEST_CRASH_HELPER", "1", 1)
        let crashController = LidSleepController(restoreSleep: { restoredAfterHelperCrash = true })
        crashController.onFailure = { reportedHelperCrash = true }
        try crashController.setEnabled(true)
        let deadline = Date().addingTimeInterval(4)
        while !reportedHelperCrash && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        unsetenv("MACSTAT_LID_TEST_CRASH_HELPER")
        precondition(reportedHelperCrash && restoredAfterHelperCrash,
                     "The parent must restore sleep if the helper is killed")
        print("Passed: idle, toggle, heartbeat, EOF, rejected enable, failure cleanup, subprocess control, parent-crash cleanup, helper-crash cleanup")
    }

    private static func waitForLog(_ expected: [String], timeout: TimeInterval = 4) {
        let path = ProcessInfo.processInfo.environment["MACSTAT_LID_TEST_LOG"]!
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let entries = (try? String(contentsOfFile: path, encoding: .utf8))?
                .split(separator: "\n").map(String.init) ?? []
            if entries == expected { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        preconditionFailure("Timed out waiting for subprocess events: \(expected)")
    }
}
