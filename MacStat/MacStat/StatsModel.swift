import Foundation
import Combine
import AppKit

/// One rendered segment of the menu bar label.
/// `image` (when set) is drawn instead of looking up `symbol` as an SF Symbol.
struct MenuBarPart {
    let symbol: String
    let text: String
    var image: NSImage? = nil
}

class StatsModel: ObservableObject {
    @Published var cpuTemp: Double? = nil
    @Published var gpuTemp: Double? = nil
    @Published var batteryTemp: Double? = nil
    @Published var cpuSpeedLimit: Int? = nil
    @Published var availableCPUs: Int? = nil
    @Published var cpuUsage: CPUUsage? = nil
    @Published var memory: MemoryInfo? = nil
    @Published var network: NetworkThroughput? = nil
    @Published var disk: DiskUsage? = nil
    @Published var battery: BatteryInfo? = nil
    @Published var diskIO: DiskIOStats? = nil
    @Published var fanSpeeds: [Double] = []
    @Published var fanPercents: [Double] = []
    @Published var menuBarParts: [MenuBarPart] = []
    var suppressLabelUpdates = false
    let hasFan: Bool

    private let smc = SMCReader()
    private var timer: Timer?
    private var settingsCancellable: AnyCancellable?

    init() {
        hasFan = smc.fanCount() > 0
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Rebuild label when settings change
        settingsCancellable = AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, !self.suppressLabelUpdates else { return }
                    self.menuBarParts = self.buildParts()
                }
            }
    }

    func refresh() {
        cpuTemp     = smc.cpuTemperature()
        gpuTemp     = smc.gpuTemperature()
        batteryTemp = smc.batteryTemperature()
        cpuUsage    = readCPUUsage()
        memory      = readMemoryInfo()
        network     = readNetworkThroughput()
        disk        = readDiskUsage()
        battery     = readBatteryInfo()
        diskIO      = readDiskIO()
        let therm   = readThermInfo()
        cpuSpeedLimit  = therm.cpuSpeedLimit
        availableCPUs  = therm.availableCPUs
        let count   = smc.fanCount()
        fanSpeeds   = count > 0 ? (0..<count).compactMap { smc.fanSpeed(index: $0) } : []
        fanPercents = (0..<fanSpeeds.count).map { i in
            guard let mx = smc.fanMaxSpeed(index: i), mx > 0 else { return 0 }
            return min(fanSpeeds[i] / mx * 100, 100)
        }
        if !suppressLabelUpdates { menuBarParts = buildParts() }
    }

    func buildParts() -> [MenuBarPart] {
        AppSettings.shared.visibleMenuBarItems.flatMap { item -> [MenuBarPart] in
            switch item {
            case .cpuTemp:
                guard let v = cpuTemp else { return [] }
                return [MenuBarPart(symbol: "thermometer.medium", text: String(format: "%.0f°", v))]
            case .gpuTemp:
                guard let v = gpuTemp else { return [] }
                return [MenuBarPart(symbol: "thermometer.high", text: String(format: "G%.0f°", v))]
            case .batteryTemp:
                guard let v = batteryTemp else { return [] }
                return [MenuBarPart(symbol: "battery.100", text: String(format: "%.0f°", v))]
            case .cpuUsage:
                guard let v = cpuUsage else { return [] }
                return [MenuBarPart(symbol: "gauge.medium", text: String(format: "%.0f%%", v.totalPercent))]
            case .cpuThrottle:
                let lim = cpuSpeedLimit ?? 100
                return [MenuBarPart(symbol: "speedometer", text: lim < 100 ? "\(lim)%▼" : "\(lim)%")]
            case .memUsed:
                guard let v = memory else { return [] }
                return [MenuBarPart(symbol: "memorychip", text: String(format: "%.0fG", v.usedGB))]
            case .memPct:
                guard let v = memory else { return [] }
                return [MenuBarPart(symbol: "memorychip.fill", text: String(format: "%d%%", v.usedPercent))]
            case .netDown:
                guard let v = network else { return [] }
                return [MenuBarPart(symbol: "arrow.down", text: formatBytes(v.rxBytesPerSec))]
            case .netUp:
                guard let v = network else { return [] }
                return [MenuBarPart(symbol: "arrow.up", text: formatBytes(v.txBytesPerSec))]
            case .fanSpeed:
                guard let v = fanSpeeds.first else { return [] }
                return [MenuBarPart(symbol: "fan", text: String(format: "%.0f", v))]
            case .fanSpeedPct:
                guard let v = fanPercents.first else { return [] }
                return [MenuBarPart(symbol: "fan.fill", text: String(format: "%.0f%%", v))]
            case .diskFree:
                guard let v = disk else { return [] }
                return [MenuBarPart(symbol: "internaldrive", text: String(format: "%.0fG", v.freeGB))]
            case .diskWrite:
                guard let v = diskIO else { return [] }
                return [MenuBarPart(symbol: "arrow.up.doc", text: formatBytes(v.writeBytesPerSec))]
            case .diskRead:
                guard let v = diskIO else { return [] }
                return [MenuBarPart(symbol: "arrow.down.doc", text: formatBytes(v.readBytesPerSec))]
            case .batteryPct:
                guard let b = battery else { return [] }
                // Charging keeps the native bolt glyph (conventional charging
                // indicator); otherwise draw a battery whose fill tracks the
                // real 0-100% level instead of a fixed ~75% symbol.
                if b.isCharging {
                    return [MenuBarPart(symbol: "battery.100.bolt", text: String(format: "%d%%", b.percent))]
                }
                return [MenuBarPart(symbol: "", text: String(format: "%d%%", b.percent),
                                    image: batteryImage(percent: b.percent))]
            }
        }
    }

    /// A battery icon whose internal fill tracks `percent` across 0-100%.
    /// Drawn by hand (outline + terminal + proportional fill) tinted to match
    /// the menu bar appearance. Custom images in an NSStatusItem attributed
    /// title don't get AppKit's automatic SF-Symbol template tinting, so we
    /// pick the color ourselves (white in dark mode, black in light).
    private func batteryImage(percent: Int) -> NSImage {
        let pct = max(0, min(100, percent))
        let W: CGFloat = 20, H: CGFloat = 10
        let color = Self.menuBarIconColor
        let img = NSImage(size: NSSize(width: W, height: H), flipped: false) { _ in
            let bodyLeft: CGFloat = 1.0, bodyRight: CGFloat = 16.0
            let bodyBottom: CGFloat = 1.5, bodyTop: CGFloat = 8.5
            let bodyW = bodyRight - bodyLeft, bodyH = bodyTop - bodyBottom

            let body = NSBezierPath(roundedRect: NSRect(x: bodyLeft, y: bodyBottom,
                                                        width: bodyW, height: bodyH),
                                    xRadius: 1.8, yRadius: 1.8)
            body.lineWidth = 1.0
            color.setStroke()
            body.stroke()

            if pct > 0 {
                let inset: CGFloat = 1.6
                let availW = bodyW - 2 * inset
                let fillW = max(1.2, availW * CGFloat(pct) / 100.0)
                let fill = NSBezierPath(roundedRect: NSRect(x: bodyLeft + inset, y: bodyBottom + inset,
                                                            width: fillW, height: bodyH - 2 * inset),
                                        xRadius: 0.8, yRadius: 0.8)
                color.setFill()
                fill.fill()
            }

            // terminal nub
            let nubH: CGFloat = 3.0, nubW: CGFloat = 2.0
            let nub = NSBezierPath(roundedRect: NSRect(x: bodyRight + 0.8,
                                                       y: (bodyBottom + bodyTop) / 2 - nubH / 2,
                                                       width: nubW, height: nubH),
                                   xRadius: 0.6, yRadius: 0.6)
            color.setFill()
            nub.fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Best-effort menu bar icon color: white in dark appearance, black in light.
    private static var menuBarIconColor: NSColor {
        let isDark = NSApp.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor.white : NSColor.black
    }
}
