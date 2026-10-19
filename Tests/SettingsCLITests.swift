// Run Tests/run-cli-tests.sh. Preferences and sockets are isolated; system services are disabled.
import Foundation
import Combine
@testable import MacStat

private final class Completion {
    private let lock = NSLock()
    private var finished = false
    private var failure: Error?

    func finish(_ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        failure = error
        finished = true
    }

    func result() -> (Bool, Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (finished, failure)
    }
}

@main
enum SettingsCLITests {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--client" {
            exit(MacStatCLI.run(Array(arguments.dropFirst(2)), send: {
                try SettingsControlClient.send($0, directory: arguments[1])
            }))
        }
        let suite = "com.azlar.macstat.cli-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, managesSystemServices: false)
        var notifications = 0
        let observation = settings.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }

        func set(_ key: String, _ value: String) -> SettingsResponse {
            SettingsCommand.handle(SettingsRequest(action: "set", key: key, value: value), settings: settings)
        }

        precondition(set("keepAwakeOnACPower", "on").settings["keepAwakeOnACPower"] == .bool(true))
        precondition(set("keepAwakeOnBattery", "1").settings["keepAwakeOnBattery"] == .bool(true))
        precondition(set("keepAwakeWithLidClosed", "true").settings["keepAwakeWithLidClosed"] == .bool(true))
        precondition(defaults.bool(forKey: "keepAwakeWhenLidClosed"), "Must use the current lid-mode persistence key")
        precondition(set("showMemory", "off").settings["showMemory"] == .bool(false))
        precondition(set("menuBarEnabled", "cpuTemp,batteryPct").error == nil)
        precondition(set("menuBarOrder", "batteryPct,cpuTemp").error == nil)
        precondition(settings.visibleMenuBarItems == [.batteryPct, .cpuTemp])
        precondition(set("popoverOrder", "battery,memory").error == nil)
        precondition(settings.popoverOrder.prefix(2) == [.battery, .memory])
        precondition(Set(settings.popoverOrder) == Set(PopoverItem.allCases))
        precondition(notifications >= 7, "CLI changes must publish to the same observers as UI changes")

        let saved = SettingsCommand.snapshot(settings)
        for (key, value) in [("showMemory", "maybe"), ("menuBarEnabled", "cpuTemp,typo"),
                             ("menuBarOrder", "cpuTemp,cpuTemp"), ("popoverOrder", "memory,"),
                             ("unknown", "true"), ("keepAwakeError", "anything")] {
            precondition(set(key, value).error != nil)
            precondition(SettingsCommand.snapshot(settings) == saved, "Invalid requests must not partially change settings")
        }
        let reloaded = AppSettings(defaults: defaults, managesSystemServices: false)
        precondition(SettingsCommand.snapshot(reloaded) == saved, "CLI settings must survive an app restart")
        precondition(set("menuBarEnabled", "none").error == nil && settings.menuBarEnabled.isEmpty)
        precondition(set("menuBarEnabled", "all").error == nil && settings.menuBarEnabled.count == MenuBarItem.allCases.count)
        precondition(set("menuBarOrder", "").error == nil && settings.menuBarOrder == MenuBarItem.allCases)
        precondition(SettingsCommand.handle(SettingsRequest(action: "delete"), settings: settings).error != nil)

        precondition(MacStatCLI.arguments([]) == nil)
        precondition(MacStatCLI.arguments(["-AppleLanguages", "(en)"]) == nil)
        precondition(MacStatCLI.arguments(["--cli"]) == [])
        let parsedRequest = try MacStatCLI.parse(["settings", "get", "showMemory", "--json"])
        precondition(parsedRequest.1)
        do {
            _ = try MacStatCLI.parse(["settings", "set", "showMemory"])
            preconditionFailure("Missing values must fail")
        } catch {}

        let directory = "/tmp/macstat-cli-tests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        // A stale socket file after a crash must be recoverable.
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        _ = FileManager.default.createFile(atPath: directory + "/control.sock", contents: Data())
        let server = SettingsControlServer(directory: directory)
        let started = try server.start {
            precondition(Thread.isMainThread, "Settings must only be accessed on the app's main thread")
            return SettingsCommand.handle($0, settings: settings)
        }
        precondition(started)
        defer { server.stop() }
        let duplicate = SettingsControlServer(directory: directory)
        let duplicateStarted = try duplicate.start { _ in SettingsResponse(error: "Wrong server") }
        precondition(!duplicateStarted,
                     "A second app must not steal the live socket")
        let completion = Completion()
        DispatchQueue.global().async {
            do {
                // Multiple CLI processes reuse one server and one settings instance.
                for index in 0..<6 {
                    let value = index % 2 == 0
                    let reply = try SettingsControlClient.send(
                        SettingsRequest(action: "set", key: "showMemory", value: value ? "on" : "off"), directory: directory)
                    precondition(reply.error == nil && reply.settings["showMemory"] == .bool(value))
                }
                let reply = try SettingsControlClient.send(SettingsRequest(action: "list"), directory: directory)
                precondition(reply.error == nil && reply.settings["showMemory"] == .bool(false))
                let unknown = try SettingsControlClient.send(SettingsRequest(action: "get", key: "typo"), directory: directory)
                precondition(unknown.error != nil)

                let json = try child(["settings", "get", "showMemory", "--json"], directory: directory)
                precondition(json.0 == 0)
                let parsed = try JSONSerialization.jsonObject(with: Data(json.1.utf8)) as! [String: Bool]
                precondition(parsed == ["showMemory": false])
                let changed = try child(["settings", "set", "showMemory", "on"], directory: directory)
                precondition(changed.0 == 0 && changed.1 == "showMemory=true\n")
                let plain = try child(["settings", "get", "showMemory"], directory: directory)
                precondition(plain.0 == 0 && plain.1 == "true\n")
                let failed = try child(["settings", "set", "showMemory", "invalid"], directory: directory)
                precondition(failed.0 != 0 && failed.1.isEmpty && failed.2.contains("expects true/false"))
                let absent = try child(["settings", "list"], directory: directory + "-absent")
                precondition(absent.0 != 0 && absent.2.contains("Cannot connect"))
                completion.finish(nil)
            } catch { completion.finish(error) }
        }
        let deadline = Date().addingTimeInterval(20)
        while !completion.result().0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(completion.result().0, "CLI socket integration timed out")
        if let error = completion.result().1 { throw error }
        precondition(settings.showMemory)
        print("Passed: CLI parsing, live notifications, persistence, validation, socket ownership, duplicate instance, process output and exit codes")
    }

    private static func child(_ arguments: [String], directory: String) throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--client", directory] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
