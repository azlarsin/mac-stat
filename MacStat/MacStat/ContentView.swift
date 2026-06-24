import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: StatsModel
    @ObservedObject var settings = AppSettings.shared
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView()
            } else {
                mainContent
            }
            Divider()
            bottomBar
        }
        .frame(width: 240)
        .onAppear { showSettings = false }
        .onReceive(NotificationCenter.default.publisher(for: .macStatOpenSettings)) { _ in
            showSettings = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .macStatResizePopover, object: nil)
            }
        }
    }

    // MARK: Main stats

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            let items = displayedPopoverItems
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index == 0 || items[index - 1].sectionTitle != item.sectionTitle {
                    sectionHeader(item.sectionTitle)
                }
                popoverItemRows(item)
            }
        }
        .padding(.vertical, 6)
    }

    private var displayedPopoverItems: [PopoverItem] {
        settings.visiblePopoverItems.filter { item in
            switch item {
            case .cpuTemp, .gpuTemp, .batteryTemp, .cpuThrottle:
                return true
            case .cpuUsage:
                return model.cpuUsage != nil
            case .memory:
                return model.memory != nil
            case .fanSpeed:
                return !model.fanSpeeds.isEmpty
            case .network:
                return model.network != nil
            case .disk:
                return model.disk != nil
            case .battery:
                return model.battery != nil
            case .diskIO:
                return model.diskIO != nil
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            if showSettings {
                Button("Save & Close") {
                    NotificationCenter.default.post(name: .macStatClosePopover, object: nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.system(size: 12, weight: .medium))
            } else {
                Text("Updated \(Date(), formatter: timeFormatter)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: {
                showSettings.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .macStatResizePopover, object: nil)
                }
            }) {
                Image(systemName: showSettings ? "chart.bar.fill" : "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(showSettings ? "Back to stats" : "Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var fanRows: some View {
        ForEach(Array(model.fanSpeeds.enumerated()), id: \.offset) { i, rpm in
            row("Fan \(i + 1)", String(format: "%.0f RPM", rpm))
        }
        ForEach(Array(model.fanPercents.enumerated()), id: \.offset) { i, pct in
            row("Fan \(i + 1) %", String(format: "%.0f%%", pct),
                color: pct > 80 ? .orange : .primary)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func popoverItemRows(_ item: PopoverItem) -> some View {
        switch item {
        case .cpuTemp:
            row("CPU", tempString(model.cpuTemp), color: tempColor(model.cpuTemp))
        case .gpuTemp:
            row("GPU", tempString(model.gpuTemp), color: tempColor(model.gpuTemp))
        case .batteryTemp:
            row("Battery", tempString(model.batteryTemp))
        case .cpuUsage:
            if let u = model.cpuUsage {
                row("Usage", String(format: "%.1f%%", u.totalPercent),
                    color: u.totalPercent > 80 ? .orange : .primary)
                row("User / Sys", String(format: "%.0f%% / %.0f%%", u.userPercent, u.systemPercent))
            }
        case .cpuThrottle:
            let lim = model.cpuSpeedLimit ?? 100
            row("Speed Limit", "\(lim)%", color: lim < 100 ? .orange : .primary)
            if let cpus = model.availableCPUs {
                row("Active CPUs", "\(cpus)")
            }
        case .memory:
            if let mem = model.memory {
                row("Used", String(format: "%.1f / %.0f GB", mem.usedGB, mem.totalGB),
                    color: mem.usedPercent > 85 ? .orange : .primary)
                row("Free", String(format: "%.1f GB", mem.freeGB))
            }
        case .fanSpeed:
            fanRows
        case .network:
            if let net = model.network {
                row("↓ Download", formatBytes(net.rxBytesPerSec))
                row("↑ Upload",   formatBytes(net.txBytesPerSec))
            }
        case .disk:
            if let disk = model.disk {
                row("Used", String(format: "%.0f / %.0f GB", disk.usedGB, disk.totalGB),
                    color: disk.usedPercent > 90 ? .orange : .primary)
                row("Free", String(format: "%.1f GB", disk.freeGB))
            }
        case .battery:
            if let bat = model.battery {
                row("Battery", "\(bat.percent)%\(bat.isCharging ? " ⚡" : "")",
                    color: bat.percent < 20 ? .orange : .primary)
            }
        case .diskIO:
            if let io = model.diskIO {
                row("Disk Read",  formatBytes(io.readBytesPerSec))
                row("Disk Write", formatBytes(io.writeBytesPerSec))
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func tempString(_ t: Double?) -> String {
        t.map { String(format: "%.1f °C", $0) } ?? "—"
    }

    private func tempColor(_ t: Double?) -> Color {
        guard let t else { return .primary }
        if t > 95 { return .red }
        if t > 80 { return .orange }
        return .primary
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()
