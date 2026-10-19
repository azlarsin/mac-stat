import Foundation

enum MacStatCLI {
    static let help = """
    Usage: mac-stat settings list [--json]
           mac-stat settings get <key> [--json]
           mac-stat settings set <key> <value> [--json]
           mac-stat install-cli [directory]
           mac-stat --version

    Examples:
      mac-stat settings set keepAwakeOnACPower on
      mac-stat settings set keepAwakeOnBattery off
      mac-stat settings set keepAwakeWithLidClosed on
      mac-stat settings set menuBarEnabled cpuTemp,cpuThrottle,batteryPct
      mac-stat settings set menuBarOrder batteryPct,cpuTemp
      mac-stat settings list --json

    Boolean values: true/false, on/off, 1/0.
    List values: comma-separated item IDs. menuBarEnabled also accepts all/none.
    Order settings append omitted items; an empty string restores the default order.
    Keys: \(SettingsCommand.keys.joined(separator: ", "))
    keepAwakeError is read-only; an empty string means no reported lid-mode error.

    MacStat must be running as the same user in a logged-in desktop session.
    Changes use the app's normal settings logic and persist across restarts.
    Run the app executable with 'install-cli' to install into ~/.local/bin by default.
    """

    /// nil means a normal macOS app launch. The installed wrapper forces CLI mode.
    static func arguments(_ arguments: [String]) -> [String]? {
        if arguments.first == "--cli" { return Array(arguments.dropFirst()) }
        guard let first = arguments.first else { return nil }
        if first.hasPrefix("-psn_") || first.hasPrefix("-NS") || first.hasPrefix("-Apple") { return nil }
        return arguments
    }

    static func run(_ arguments: [String],
                    send: (SettingsRequest) throws -> SettingsResponse = { try SettingsControlClient.send($0) }) -> Int32 {
        do {
            if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] || arguments == ["help"]
                || arguments == ["settings", "--help"] {
                print(help)
                return 0
            }
            if arguments == ["--version"] {
                print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
                return 0
            }
            if arguments.first == "install-cli" {
                guard arguments.count <= 2 else { throw ControlError("Usage: mac-stat install-cli [directory]") }
                let target = try install(directory: arguments.count == 2 ? arguments[1] : nil)
                print("Installed \(target.path)")
                let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
                if !pathDirectories.contains(target.deletingLastPathComponent().path) {
                    print("Add this directory to PATH in your shell configuration: \(target.deletingLastPathComponent().path)")
                }
                return 0
            }
            let (request, json) = try parse(arguments)
            let response = try send(request)
            if let error = response.error { throw ControlError(error) }
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(response.settings), as: UTF8.self))
            } else if request.action == "get", let key = request.key {
                guard let value = response.settings[key] else {
                    throw ControlError("MacStat did not return '\(key)'. Make sure the app and CLI use the same version.")
                }
                print(value.display)
            } else {
                for key in response.settings.keys.sorted() { print("\(key)=\(response.settings[key]!.display)") }
            }
            return 0
        } catch {
            let text = "mac-stat: \(error.localizedDescription)\n"
            try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
            return 1
        }
    }

    static func parse(_ arguments: [String]) throws -> (SettingsRequest, Bool) {
        var args = arguments
        let json = args.last == "--json"
        if json { args.removeLast() }
        guard args.first == "settings", args.count >= 2 else { throw ControlError(help) }
        switch args[1] {
        case "list" where args.count == 2:
            return (SettingsRequest(action: "list"), json)
        case "get" where args.count == 3:
            return (SettingsRequest(action: "get", key: args[2]), json)
        case "set" where args.count == 4:
            return (SettingsRequest(action: "set", key: args[2], value: args[3]), json)
        default: throw ControlError("Usage: mac-stat settings list | get <key> | set <key> <value> [--json]")
        }
    }

    @discardableResult
    static func install(directory: String? = nil) throws -> URL {
        guard let executable = Bundle.main.executableURL else {
            throw ControlError(String(localized: "Cannot locate the MacStat executable."))
        }
        let targetDirectory = directory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let target = targetDirectory.appendingPathComponent("mac-stat")
        let marker = "# MacStat command-line launcher"
        if FileManager.default.fileExists(atPath: target.path) {
            let existing = try? String(contentsOf: target, encoding: .utf8)
            guard existing?.hasPrefix("#!/bin/sh\n\(marker)\n") == true else {
                throw ControlError(String(localized: "Refusing to overwrite an existing command at \(target.path)"))
            }
        }
        let escaped = executable.resolvingSymlinksInPath().path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\n\(marker)\nexec '\(escaped)' --cli \"$@\"\n"
        try script.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        return target
    }
}
