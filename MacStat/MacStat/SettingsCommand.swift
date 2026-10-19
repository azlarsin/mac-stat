import Foundation
import ServiceManagement

enum SettingsCommand {
    static let boolKeys: [String: ReferenceWritableKeyPath<AppSettings, Bool>] = [
        "keepAwakeOnACPower": \.keepAwakeOnACPower,
        "keepAwakeOnBattery": \.keepAwakeOnBattery,
        "keepAwakeWithLidClosed": \.keepAwakeWithLidClosed,
        "launchAtLogin": \.launchAtLogin,
        "showCPUTemp": \.showCPUTemp,
        "showGPUTemp": \.showGPUTemp,
        "showBatteryTemp": \.showBatteryTemp,
        "showCPUUsage": \.showCPUUsage,
        "showThrottle": \.showThrottle,
        "showMemory": \.showMemory,
        "showNetwork": \.showNetwork,
        "showDisk": \.showDisk,
        "showDiskIO": \.showDiskIO,
        "showFan": \.showFan,
        "showBattery": \.showBattery,
        "showBatteryChargeRate": \.showBatteryChargeRate,
    ]

    static var keys: [String] {
        (Array(boolKeys.keys) + ["menuBarEnabled", "menuBarOrder", "popoverOrder", "keepAwakeError"]).sorted()
    }

    static func snapshot(_ settings: AppSettings) -> [String: SettingValue] {
        var result = boolKeys.mapValues { SettingValue.bool(settings[keyPath: $0]) }
        result["menuBarEnabled"] = .items(settings.menuBarOrder.filter { settings.menuBarEnabled.contains($0) }.map(menuBarID))
        result["menuBarOrder"] = .items(settings.menuBarOrder.map(menuBarID))
        result["popoverOrder"] = .items(settings.popoverOrder.map(popoverID))
        result["keepAwakeError"] = .text(settings.keepAwakeError ?? "")
        return result
    }

    static func handle(_ request: SettingsRequest, settings: AppSettings) -> SettingsResponse {
        do {
            switch request.action {
            case "list":
                return SettingsResponse(settings: snapshot(settings))
            case "get", "set":
                guard let key = request.key, keys.contains(key) else {
                    throw ControlError("Unknown setting '\(request.key ?? "")'. Use 'mac-stat settings list' to see available keys.")
                }
                if request.action == "set" {
                    guard let value = request.value else { throw ControlError("A setting value is required.") }
                    try set(key, value: value, settings: settings)
                }
                return SettingsResponse(settings: [key: snapshot(settings)[key]!])
            default:
                throw ControlError("Unknown settings action '\(request.action)'.")
            }
        } catch { return SettingsResponse(error: error.localizedDescription) }
    }

    private static func set(_ key: String, value: String, settings: AppSettings) throws {
        if let path = boolKeys[key] {
            let enabled: Bool
            switch value.lowercased() {
            case "true", "on", "1": enabled = true
            case "false", "off", "0": enabled = false
            default: throw ControlError("\(key) expects true/false, on/off, or 1/0.")
            }
            settings[keyPath: path] = enabled
            if key == "launchAtLogin", let error = settings.launchAtLoginError {
                throw ControlError("Could not change Launch at Login: \(error.localizedDescription)")
            }
            if key == "launchAtLogin", settings.managesSystemServices,
               SMAppService.mainApp.status == .requiresApproval {
                throw ControlError("Launch at Login requires approval in macOS System Settings > General > Login Items.")
            }
            return
        }
        switch key {
        case "menuBarEnabled":
            let items = try parseItems(value, all: MenuBarItem.allCases, id: menuBarID, allowSelection: true)
            settings.menuBarEnabled = Set(items)
        case "menuBarOrder":
            let items = try parseItems(value, all: MenuBarItem.allCases, id: menuBarID)
            settings.menuBarOrder = items + MenuBarItem.allCases.filter { !items.contains($0) }
        case "popoverOrder":
            let items = try parseItems(value, all: PopoverItem.allCases, id: popoverID)
            settings.popoverOrder = items + PopoverItem.allCases.filter { !items.contains($0) }
        default: throw ControlError("\(key) is read-only.")
        }
    }

    private static func parseItems<T: Equatable>(_ value: String, all: [T], id: (T) -> String,
                                                 allowSelection: Bool = false) throws -> [T] {
        if allowSelection && value == "all" { return all }
        if value.isEmpty || (allowSelection && value == "none") { return [] }
        let names = value.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [T] = []
        for name in names {
            guard let item = all.first(where: { id($0) == name }) else {
                throw ControlError("Unknown item '\(name)'. Available items: \(all.map(id).joined(separator: ","))")
            }
            guard !result.contains(item) else { throw ControlError("Duplicate item '\(name)'.") }
            result.append(item)
        }
        return result
    }

    private static func menuBarID(_ item: MenuBarItem) -> String { String(item.rawValue.dropFirst(3)) }
    private static func popoverID(_ item: PopoverItem) -> String { String(item.rawValue.dropFirst(8)) }
}
