import Foundation
import Combine

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
    @Published var menuBarParts: [(symbol: String, text: String)] = []
    var suppressLabelUpdates = false

    private let smc = SMCReader()
    private var timer: Timer?
    private var settingsCancellable: AnyCancellable?

    init() {
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

    func buildParts() -> [(symbol: String, text: String)] {
        AppSettings.shared.visibleMenuBarItems.compactMap { item -> (String, String)? in
            switch item {
            case .cpuTemp:
                return cpuTemp.map { ("thermometer.medium", String(format: "%.0f°", $0)) }
            case .gpuTemp:
                return gpuTemp.map { ("thermometer.high", String(format: "G%.0f°", $0)) }
            case .batteryTemp:
                return batteryTemp.map { ("battery.100", String(format: "%.0f°", $0)) }
            case .cpuUsage:
                return cpuUsage.map { ("gauge.medium", String(format: "%.0f%%", $0.totalPercent)) }
            case .cpuThrottle:
                guard let lim = cpuSpeedLimit else { return nil }
                return ("speedometer", lim < 100 ? "\(lim)%▼" : "\(lim)%")
            case .memUsed:
                return memory.map { ("memorychip", String(format: "%.0fG", $0.usedGB)) }
            case .memPct:
                return memory.map { ("memorychip", String(format: "%d%%", $0.usedPercent)) }
            case .netDown:
                return network.map { ("arrow.down", formatBytes($0.rxBytesPerSec)) }
            case .netUp:
                return network.map { ("arrow.up", formatBytes($0.txBytesPerSec)) }
            case .fanSpeed:
                return fanSpeeds.first.map { ("fan", String(format: "%.0f", $0)) }
            case .fanSpeedPct:
                return fanPercents.first.map { ("fan.fill", String(format: "%.0f%%", $0)) }
            case .diskFree:
                return disk.map { ("internaldrive", String(format: "%.0fG", $0.freeGB)) }
            case .diskWrite:
                return diskIO.map { ("arrow.up.doc", formatBytes($0.writeBytesPerSec)) }
            case .diskRead:
                return diskIO.map { ("arrow.down.doc", formatBytes($0.readBytesPerSec)) }
            case .batteryPct:
                guard let b = battery else { return nil }
                let sym = b.isCharging ? "battery.100.bolt" : "battery.75"
                return (sym, "\(b.percent)%")
            }
        }
    }
}
