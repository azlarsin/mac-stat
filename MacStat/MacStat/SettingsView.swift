import SwiftUI
import AppKit
import IOKit.ps
import ServiceManagement
import UniformTypeIdentifiers

enum MenuBarItem: String, CaseIterable {
    case cpuTemp      = "mb_cpuTemp"
    case gpuTemp      = "mb_gpuTemp"
    case batteryTemp  = "mb_batteryTemp"
    case cpuUsage     = "mb_cpuUsage"
    case cpuThrottle  = "mb_cpuThrottle"
    case memUsed      = "mb_memUsed"
    case memPct       = "mb_memPct"
    case netDown      = "mb_netDown"
    case netUp        = "mb_netUp"
    case fanSpeed     = "mb_fanSpeed"
    case fanSpeedPct  = "mb_fanSpeedPct"
    case diskFree     = "mb_diskFree"
    case diskWrite    = "mb_diskWrite"
    case diskRead     = "mb_diskRead"
    case batteryPct   = "mb_batteryPct"
    case batteryChargeRate = "mb_batteryChargeRate"

    var label: String {
        switch self {
        case .cpuTemp:     return "CPU Temp"
        case .gpuTemp:     return "GPU Temp"
        case .batteryTemp: return "Battery Temp"
        case .cpuUsage:    return "CPU Usage %"
        case .cpuThrottle: return "CPU Throttle"
        case .memUsed:     return "Memory Used GB"
        case .memPct:      return "Memory Used %"
        case .netDown:     return "Net ↓"
        case .netUp:       return "Net ↑"
        case .fanSpeed:    return "Fan Speed RPM"
        case .fanSpeedPct: return "Fan Speed %"
        case .diskFree:    return "Disk Free"
        case .diskWrite:   return "Disk Write"
        case .diskRead:    return "Disk Read"
        case .batteryPct:  return "Battery %"
        case .batteryChargeRate: return "Battery Charge Speed"
        }
    }

    var symbol: String {
        switch self {
        case .cpuTemp:           return "thermometer.medium"
        case .gpuTemp:           return "thermometer.high"
        case .batteryTemp:       return "battery.100"
        case .cpuUsage:          return "gauge.medium"
        case .cpuThrottle:       return "speedometer"
        case .memUsed:           return "memorychip"
        case .memPct:            return "memorychip.fill"
        case .netDown:           return "arrow.down"
        case .netUp:             return "arrow.up"
        case .fanSpeed:          return "fan"
        case .fanSpeedPct:       return "fan.fill"
        case .diskFree:          return "internaldrive"
        case .diskWrite:         return "arrow.up.doc"
        case .diskRead:          return "arrow.down.doc"
        case .batteryPct:        return "battery.100"
        case .batteryChargeRate: return "bolt.fill"
        }
    }
}

enum PopoverItem: String, CaseIterable {
    case cpuTemp     = "popover_cpuTemp"
    case gpuTemp     = "popover_gpuTemp"
    case batteryTemp = "popover_batteryTemp"
    case cpuUsage    = "popover_cpuUsage"
    case cpuThrottle = "popover_cpuThrottle"
    case memory      = "popover_memory"
    case fanSpeed    = "popover_fanSpeed"
    case network     = "popover_network"
    case disk        = "popover_disk"
    case diskIO      = "popover_diskIO"
    case battery     = "popover_battery"
    case batteryChargeRate = "popover_batteryChargeRate"

    var label: String {
        switch self {
        case .cpuTemp:     return "CPU Temperature"
        case .gpuTemp:     return "GPU Temperature"
        case .batteryTemp: return "Battery Temperature"
        case .cpuUsage:    return "CPU Usage"
        case .cpuThrottle: return "CPU Throttle"
        case .memory:      return "Memory"
        case .fanSpeed:    return "Fan Speed"
        case .network:     return "Network"
        case .disk:        return "Disk"
        case .battery:     return "Battery"
        case .diskIO:      return "Disk I/O"
        case .batteryChargeRate: return "Battery Charge Speed"
        }
    }

    var sectionTitle: String {
        switch self {
        case .cpuTemp, .gpuTemp, .batteryTemp:
            return "TEMPERATURE"
        case .cpuUsage, .cpuThrottle:
            return "CPU"
        case .memory:
            return "MEMORY"
        case .fanSpeed:
            return "FAN"
        case .network:
            return "NETWORK"
        case .disk, .diskIO:
            return "DISK"
        case .battery, .batteryChargeRate:
            return "BATTERY"
        }
    }

    var symbol: String {
        switch self {
        case .cpuTemp:           return "thermometer.medium"
        case .gpuTemp:           return "thermometer.high"
        case .batteryTemp:       return "battery.100"
        case .cpuUsage:          return "gauge.medium"
        case .cpuThrottle:       return "speedometer"
        case .memory:            return "memorychip"
        case .fanSpeed:          return "fan"
        case .network:           return "arrow.down.arrow.up"
        case .disk:              return "internaldrive"
        case .diskIO:            return "arrow.left.arrow.right"
        case .battery:           return "battery.100"
        case .batteryChargeRate: return "bolt.fill"
        }
    }
}

private let kMenuBarOrderKey = "mb_order"
private let kMenuBarEnabledKey = "mb_enabled"
private let kPopoverOrderKey = "popover_order"
private let kDefaultMenuBarEnabled: Set<MenuBarItem> = [.cpuTemp, .cpuThrottle]

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults: UserDefaults
    // Tests can use isolated preferences without changing the Mac's power policy.
    let managesSystemServices: Bool
    private(set) var launchAtLoginError: Error?

    // Popover sections
    @Published var showCPUTemp: Bool     { didSet { saveBool("showCPUTemp", showCPUTemp) } }
    @Published var showGPUTemp: Bool     { didSet { saveBool("showGPUTemp", showGPUTemp) } }
    @Published var showBatteryTemp: Bool { didSet { saveBool("showBatteryTemp", showBatteryTemp) } }
    @Published var showCPUUsage: Bool    { didSet { saveBool("showCPUUsage", showCPUUsage) } }
    @Published var showMemory: Bool      { didSet { saveBool("showMemory", showMemory) } }
    @Published var showNetwork: Bool     { didSet { saveBool("showNetwork", showNetwork) } }
    @Published var showDisk: Bool        { didSet { saveBool("showDisk", showDisk) } }
    @Published var showFan: Bool         { didSet { saveBool("showFan", showFan) } }
    @Published var showThrottle: Bool    { didSet { saveBool("showThrottle", showThrottle) } }
    @Published var showBattery: Bool     { didSet { saveBool("showBattery", showBattery) } }
    @Published var showDiskIO: Bool      { didSet { saveBool("showDiskIO", showDiskIO) } }
    @Published var showBatteryChargeRate: Bool {
        didSet { saveBool("showBatteryChargeRate", showBatteryChargeRate) }
    }

    // Ordered list of all popover items; only checked items are rendered.
    @Published var popoverOrder: [PopoverItem] = [] {
        didSet { savePopoverOrder() }
    }

    // Ordered list of all menubar items; only checked items are rendered.
    @Published var menuBarOrder: [MenuBarItem] = [] {
        didSet { saveMenuBarOrder() }
    }

    @Published var menuBarEnabled: Set<MenuBarItem> = [] {
        didSet { saveMenuBarEnabled() }
    }

    // Launch at login
    @Published var launchAtLogin: Bool = false {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    @Published var keepAwakeOnACPower: Bool = false {
        didSet {
            saveBool("keepAwakeOnACPower", keepAwakeOnACPower)
            applyKeepAwake()
        }
    }

    @Published var keepAwakeOnBattery: Bool = false {
        didSet {
            saveBool("keepAwakeOnBattery", keepAwakeOnBattery)
            applyKeepAwake()
        }
    }

    @Published var keepAwakeWithLidClosed: Bool = false {
        didSet {
            // The old similarly named key only enabled caffeinate on AC power.
            saveBool("keepAwakeWhenLidClosed", keepAwakeWithLidClosed)
            keepAwakeError = nil
            applyKeepAwake()
        }
    }

    @Published private(set) var keepAwakeError: String?
    private let lidSleepController = LidSleepController()
    private var caffeinateProcess: Process?
    private var powerSourceRunLoopSource: CFRunLoopSource?

    init(defaults: UserDefaults = .standard, managesSystemServices: Bool = true) {
        self.defaults = defaults
        self.managesSystemServices = managesSystemServices
        func b(_ key: String, _ def: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
        }
        showCPUTemp     = b("showCPUTemp", true)
        showGPUTemp     = b("showGPUTemp", true)
        showBatteryTemp = b("showBatteryTemp", true)
        showCPUUsage    = b("showCPUUsage", true)
        showMemory      = b("showMemory", true)
        showNetwork     = b("showNetwork", true)
        showDisk        = b("showDisk", true)
        showFan         = b("showFan", true)
        showThrottle    = b("showThrottle", true)
        showBattery     = b("showBattery", true)
        showDiskIO      = b("showDiskIO", true)
        showBatteryChargeRate = b("showBatteryChargeRate", true)

        if let saved = defaults.stringArray(forKey: kPopoverOrderKey) {
            popoverOrder = Self.normalizedPopoverOrder(saved.compactMap { PopoverItem(rawValue: $0) })
        } else {
            popoverOrder = PopoverItem.allCases
        }

        let savedMenuBarOrder = defaults.stringArray(forKey: kMenuBarOrderKey)?
            .compactMap { MenuBarItem(rawValue: $0) }
        menuBarOrder = Self.normalizedMenuBarOrder(savedMenuBarOrder ?? [])

        if let enabled = defaults.stringArray(forKey: kMenuBarEnabledKey) {
            menuBarEnabled = Set(enabled.compactMap { MenuBarItem(rawValue: $0) })
        } else if let savedMenuBarOrder, !savedMenuBarOrder.isEmpty {
            menuBarEnabled = Set(savedMenuBarOrder)
        } else {
            menuBarEnabled = kDefaultMenuBarEnabled
        }

        if managesSystemServices, #available(macOS 13.0, *) {
            _launchAtLogin = Published(initialValue: SMAppService.mainApp.status == .enabled)
        }

        _keepAwakeOnACPower = Published(
            initialValue: b("keepAwakeOnACPower", b("keepAwakeWithLidClosed", false))
        )
        _keepAwakeOnBattery = Published(
            initialValue: b("keepAwakeOnBattery", false)
        )
        _keepAwakeWithLidClosed = Published(
            initialValue: b("keepAwakeWhenLidClosed", false)
        )
        lidSleepController.onFailure = { [weak self] in
            self?.disableLidClosedKeepAwake()
        }
        observePowerSourceChanges()
        applyKeepAwake()
    }

    deinit {
        if let source = powerSourceRunLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        stopKeepAwakeProcess()
    }

    var visiblePopoverItems: [PopoverItem] {
        popoverOrder.filter { isPopoverItemVisible($0) }
    }

    var visibleMenuBarItems: [MenuBarItem] {
        menuBarOrder.filter { menuBarEnabled.contains($0) }
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        launchAtLoginError = nil
        guard managesSystemServices else { return }
        guard #available(macOS 13.0, *) else { return }
        let status = SMAppService.mainApp.status
        guard enable ? status != .enabled : (status == .enabled || status == .requiresApproval) else { return }
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error
            DispatchQueue.main.async { self.launchAtLogin = !enable }
        }
    }

    private func observePowerSourceChanges() {
        guard managesSystemServices else { return }
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let settings = Unmanaged<AppSettings>.fromOpaque(context).takeUnretainedValue()
            settings.applyKeepAwake()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else { return }

        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func applyKeepAwake() {
        guard managesSystemServices else { return }
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSource = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else {
            stopCaffeinateProcess()
            applyLidClosedKeepAwake(false)
            return
        }

        let onBattery = powerSource as String != kIOPMACPowerKey
        let enabled = onBattery ? keepAwakeOnBattery : keepAwakeOnACPower
        guard enabled else {
            stopCaffeinateProcess()
            applyLidClosedKeepAwake(false)
            return
        }

        // -s only works on AC; -i prevents idle sleep on battery as well.
        let arguments = [onBattery ? "-i" : "-s",
                         "-w", String(ProcessInfo.processInfo.processIdentifier)]
        applyLidClosedKeepAwake(keepAwakeWithLidClosed)
        guard caffeinateProcess?.isRunning != true || caffeinateProcess?.arguments != arguments
        else { return }

        stopCaffeinateProcess()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = arguments
        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let self, self.caffeinateProcess === process else { return }
                self.caffeinateProcess = nil
                self.disableKeepAwake(onBattery: onBattery)
            }
        }

        do {
            try process.run()
            caffeinateProcess = process
        } catch {
            DispatchQueue.main.async {
                guard self.caffeinateProcess == nil else { return }
                self.disableKeepAwake(onBattery: onBattery)
            }
        }
    }

    private func disableKeepAwake(onBattery: Bool) {
        if onBattery {
            keepAwakeOnBattery = false
        } else {
            keepAwakeOnACPower = false
        }
    }

    private func applyLidClosedKeepAwake(_ enabled: Bool) {
        do {
            try lidSleepController.setEnabled(enabled)
        } catch {
            lidSleepController.stop()
            DispatchQueue.main.async { self.disableLidClosedKeepAwake() }
        }
    }

    private func disableLidClosedKeepAwake() {
        keepAwakeWithLidClosed = false
        keepAwakeError = String(localized: "Couldn't enable lid-closed mode on this Mac.")
    }

    func stopKeepAwakeProcess() {
        lidSleepController.stop()
        stopCaffeinateProcess()
    }

    private func stopCaffeinateProcess() {
        let process = caffeinateProcess
        caffeinateProcess = nil
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func isPopoverItemVisible(_ item: PopoverItem) -> Bool {
        switch item {
        case .cpuTemp:     return showCPUTemp
        case .gpuTemp:     return showGPUTemp
        case .batteryTemp: return showBatteryTemp
        case .cpuUsage:    return showCPUUsage
        case .cpuThrottle: return showThrottle
        case .memory:      return showMemory
        case .fanSpeed:    return showFan
        case .network:     return showNetwork
        case .disk:        return showDisk
        case .battery:     return showBattery
        case .diskIO:      return showDiskIO
        case .batteryChargeRate: return showBatteryChargeRate
        }
    }

    func setPopoverItem(_ item: PopoverItem, visible: Bool) {
        switch item {
        case .cpuTemp:     showCPUTemp = visible
        case .gpuTemp:     showGPUTemp = visible
        case .batteryTemp: showBatteryTemp = visible
        case .cpuUsage:    showCPUUsage = visible
        case .cpuThrottle: showThrottle = visible
        case .memory:      showMemory = visible
        case .fanSpeed:    showFan = visible
        case .network:     showNetwork = visible
        case .disk:        showDisk = visible
        case .battery:     showBattery = visible
        case .diskIO:      showDiskIO = visible
        case .batteryChargeRate: showBatteryChargeRate = visible
        }
    }

    func isInMenuBar(_ item: MenuBarItem) -> Bool {
        menuBarEnabled.contains(item)
    }

    func toggleMenuBar(_ item: MenuBarItem) {
        if menuBarEnabled.contains(item) {
            menuBarEnabled.remove(item)
        } else {
            menuBarEnabled.insert(item)
        }
    }

    func movePopoverItems(fromOffsets: IndexSet, toOffset: Int) {
        popoverOrder.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func moveMenuBarItems(fromOffsets: IndexSet, toOffset: Int) {
        menuBarOrder.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func setAllPopover(_ items: [PopoverItem], visible: Bool) {
        for item in items { setPopoverItem(item, visible: visible) }
    }

    func setAllMenuBar(_ items: [MenuBarItem], enabled: Bool) {
        // Assign a brand-new Set instead of mutating in place. @Published does
        // not fire objectWillChange (and the didSet that persists the choice is
        // not invoked) for in-place mutations such as formUnion/subtract — that
        // left the menubar label stale after "Select All" and, in the worst
        // case, the status item stopped updating until restart. Going through
        // the setter guarantees the Combine sink + saveMenuBarEnabled() fire.
        menuBarEnabled = enabled
            ? menuBarEnabled.union(items)
            : menuBarEnabled.subtracting(items)
    }

    func resetPopoverOrder() {
        popoverOrder = PopoverItem.allCases
        for item in PopoverItem.allCases { setPopoverItem(item, visible: true) }
    }

    func resetMenuBarOrder() {
        menuBarOrder = MenuBarItem.allCases
        menuBarEnabled = kDefaultMenuBarEnabled
    }

    private func savePopoverOrder() {
        defaults.set(popoverOrder.map(\.rawValue), forKey: kPopoverOrderKey)
    }

    private func saveMenuBarOrder() {
        defaults.set(menuBarOrder.map(\.rawValue), forKey: kMenuBarOrderKey)
    }

    private func saveMenuBarEnabled() {
        let enabled = menuBarOrder.filter { menuBarEnabled.contains($0) }
        defaults.set(enabled.map(\.rawValue), forKey: kMenuBarEnabledKey)
    }

    private func saveBool(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
    }

    private static func normalizedPopoverOrder(_ saved: [PopoverItem]) -> [PopoverItem] {
        var result = normalizedOrder(saved, allItems: PopoverItem.allCases)

        // Put this newly introduced item beside Battery for existing users,
        // while preserving every item they have already reordered.
        if !saved.contains(.batteryChargeRate),
           let chargeRateIndex = result.firstIndex(of: .batteryChargeRate),
           let batteryIndex = result.firstIndex(of: .battery) {
            result.remove(at: chargeRateIndex)
            result.insert(.batteryChargeRate, at: batteryIndex + 1)
        }
        return result
    }

    private static func normalizedMenuBarOrder(_ saved: [MenuBarItem]) -> [MenuBarItem] {
        normalizedOrder(saved, allItems: MenuBarItem.allCases)
    }

    private static func normalizedOrder<T: Hashable>(_ saved: [T], allItems: [T]) -> [T] {
        var seen = Set<T>()
        let uniqueSaved = saved.filter { seen.insert($0).inserted }
        return uniqueSaved + allItems.filter { !seen.contains($0) }
    }
}

struct SettingsView: View {
    @ObservedObject var s = AppSettings.shared
    @EnvironmentObject var model: StatsModel
    @State private var draggingPopoverItem: PopoverItem?
    @State private var draggingMenuBarItem: MenuBarItem?
    @State private var hoveringPopoverItem: PopoverItem?
    @State private var hoveringMenuBarItem: MenuBarItem?
    @State private var isDraggingSortItem = false
    @State private var cliInstalled = false
    @State private var cliInstallError: String?

    private func isFanItem(_ item: PopoverItem) -> Bool { item == .fanSpeed }
    private func isFanItem(_ item: MenuBarItem) -> Bool { item == .fanSpeed || item == .fanSpeedPct }

    private var displayedPopoverItems: [PopoverItem] {
        s.popoverOrder.filter { !isFanItem($0) || model.hasFan }
    }
    private var displayedMenuBarItems: [MenuBarItem] {
        s.menuBarOrder.filter { !isFanItem($0) || model.hasFan }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Popover Items") { s.resetPopoverOrder() }
                ForEach(displayedPopoverItems, id: \.self) { item in
                    popoverRow(item)
                        .onDrop(
                            of: [.text],
                            delegate: PopoverItemDropDelegate(
                                item: item,
                                settings: s,
                                draggingItem: $draggingPopoverItem,
                                dragEnded: finishSortDrag
                            )
                        )
                }
                selectAllRow(isOn: Binding(
                    get: { displayedPopoverItems.allSatisfy { s.isPopoverItemVisible($0) } },
                    set: { on in s.setAllPopover(displayedPopoverItems, visible: on) }
                ))

                Divider().padding(.vertical, 8)

                sectionHeader("Menu Bar Items") { s.resetMenuBarOrder() }
                ForEach(displayedMenuBarItems, id: \.self) { item in
                    menuBarRow(item)
                        .onDrop(
                            of: [.text],
                            delegate: MenuBarItemDropDelegate(
                                item: item,
                                settings: s,
                                draggingItem: $draggingMenuBarItem,
                                dragEnded: finishSortDrag
                            )
                        )
                }
                selectAllRow(isOn: Binding(
                    get: { displayedMenuBarItems.allSatisfy { s.isInMenuBar($0) } },
                    set: { on in s.setAllMenuBar(displayedMenuBarItems, enabled: on) }
                ))

                Divider().padding(.vertical, 8)

                keepAwakeRow

                Divider().padding(.vertical, 8)

                launchAtLoginRow

                Divider().padding(.vertical, 8)

                commandLineRow
        }
        .padding(12)
        .frame(width: 240)
        .onReceive(s.$keepAwakeError) { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .macStatResizePopover, object: nil)
            }
        }
    }

    private var commandLineRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: installCommandLineTool) {
                Label("Install Command Line Tool", systemImage: "terminal")
                    .frame(maxWidth: .infinity)
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)

            Text("Run ~/.local/bin/mac-stat in Terminal or over SSH.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if cliInstalled {
                Text("Command line tool installed.")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
            }
            if let cliInstallError {
                Text(cliInstallError)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private func installCommandLineTool() {
        do {
            try MacStatCLI.install()
            cliInstalled = true
            cliInstallError = nil
        } catch {
            cliInstalled = false
            cliInstallError = String(localized: "Couldn't install the command line tool: \(error.localizedDescription)")
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .macStatResizePopover, object: nil)
        }
    }

    private var keepAwakeRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            toggle("Keep Awake on AC Power", $s.keepAwakeOnACPower)
                .padding(.horizontal, 0)
            toggle("Keep Awake on Battery", $s.keepAwakeOnBattery)
                .padding(.horizontal, 0)
            toggle("Keep Awake with Lid Closed", $s.keepAwakeWithLidClosed)
                .padding(.horizontal, 0)
            Text("Lid-closed mode follows the AC and battery choices. Screen saver and auto-lock still work.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            if let error = s.keepAwakeError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var launchAtLoginRow: some View {
        let inApps = Bundle.main.bundlePath.hasPrefix("/Applications")
        if inApps {
            toggle("Launch at Login", $s.launchAtLogin)
                .padding(.horizontal, 0)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                toggle("Launch at Login", $s.launchAtLogin)
                    .padding(.horizontal, 0)
                    .disabled(true)
                Text("Move app to /Applications to enable")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func popoverRow(_ item: PopoverItem) -> some View {
        let isHovered = hoveringPopoverItem == item
        let isDragging = draggingPopoverItem == item

        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { s.isPopoverItemVisible(item) },
                set: { s.setPopoverItem(item, visible: $0) }
            )) {
                settingsItemLabel(
                    item.label,
                    symbol: item.symbol,
                    isEnabled: s.isPopoverItemVisible(item)
                )
            }
            .toggleStyle(.checkbox)

            Spacer()

            dragHandle(isActive: isHovered || isDragging)
                .onDrag {
                    draggingPopoverItem = item
                    isDraggingSortItem = true
                    NSCursor.closedHand.set()
                    return NSItemProvider(object: item.rawValue as NSString)
                }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(rowHighlight(isDragging: isDragging))
        .onHover { hovering in
            hoveringPopoverItem = hovering ? item : nil
        }
    }

    @ViewBuilder
    private func menuBarRow(_ item: MenuBarItem) -> some View {
        let isHovered = hoveringMenuBarItem == item
        let isDragging = draggingMenuBarItem == item

        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { s.isInMenuBar(item) },
                set: { _ in s.toggleMenuBar(item) }
            )) {
                settingsItemLabel(
                    item.label,
                    symbol: item.symbol,
                    isEnabled: s.isInMenuBar(item)
                )
            }
            .toggleStyle(.checkbox)

            Spacer()

            dragHandle(isActive: isHovered || isDragging)
                .onDrag {
                    draggingMenuBarItem = item
                    isDraggingSortItem = true
                    NSCursor.closedHand.set()
                    return NSItemProvider(object: item.rawValue as NSString)
                }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(rowHighlight(isDragging: isDragging))
        .onHover { hovering in
            hoveringMenuBarItem = hovering ? item : nil
        }
    }

    @ViewBuilder
    private func dragHandle(isActive: Bool) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .frame(width: 8, height: 0.5)
            }
        }
            .foregroundStyle(isActive ? .tertiary : .quaternary)
            .opacity(isActive ? 1 : 0.55)
            .frame(width: 22, height: 18)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard !isDraggingSortItem else { return }
                if hovering {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .help("Drag to reorder")
    }

    @ViewBuilder
    private func settingsItemLabel(_ text: String, symbol: String, isEnabled: Bool) -> some View {
        Label {
            Text(LocalizedStringKey(text))
        } icon: {
            Image(systemName: symbol)
                .frame(width: 14)
        }
        .font(.system(size: 12))
        .foregroundStyle(isEnabled ? .primary : .secondary)
    }

    private func finishSortDrag() {
        draggingPopoverItem = nil
        draggingMenuBarItem = nil
        isDraggingSortItem = false
        NSCursor.arrow.set()
    }

    private func rowHighlight(isDragging: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isDragging ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private func header(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func sectionHeader(_ text: LocalizedStringKey, onReset: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Restore defaults") { onReset() }
                .buttonStyle(.plain)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func selectAllRow(isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text("Select All")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 1)
    }

    @ViewBuilder
    private func toggle(_ label: LocalizedStringKey, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
    }
}

private struct PopoverItemDropDelegate: DropDelegate {
    let item: PopoverItem
    let settings: AppSettings
    @Binding var draggingItem: PopoverItem?
    let dragEnded: () -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggingItem,
            draggingItem != item,
            let from = settings.popoverOrder.firstIndex(of: draggingItem),
            let to = settings.popoverOrder.firstIndex(of: item)
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            settings.movePopoverItems(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragEnded()
        return true
    }
}

private struct MenuBarItemDropDelegate: DropDelegate {
    let item: MenuBarItem
    let settings: AppSettings
    @Binding var draggingItem: MenuBarItem?
    let dragEnded: () -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggingItem,
            draggingItem != item,
            let from = settings.menuBarOrder.firstIndex(of: draggingItem),
            let to = settings.menuBarOrder.firstIndex(of: item)
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            settings.moveMenuBarItems(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragEnded()
        return true
    }
}
