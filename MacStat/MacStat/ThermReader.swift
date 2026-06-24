import Foundation

// Parses `pmset -g therm` output to get CPU speed limit percentage.
// Also tries `powermetrics` for instantaneous CPU frequency (requires sudo, skipped here).
// Falls back to sysctl hw.cpufrequency for nominal frequency.
struct ThermInfo {
    var cpuSpeedLimit: Int?    // percent from pmset (100 = not throttled)
    var schedulerLimit: Int?
    var availableCPUs: Int?
}

func readThermInfo() -> ThermInfo {
    var info = ThermInfo()
    guard let output = runCommand("/usr/bin/pmset", args: ["-g", "therm"]) else { return info }

    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("CPU_Speed_Limit"), let v = parseValue(trimmed) {
            info.cpuSpeedLimit = v
        } else if trimmed.hasPrefix("Scheduler_Limit"), let v = parseValue(trimmed) {
            info.schedulerLimit = v
        } else if trimmed.hasPrefix("Available_CPUs"), let v = parseValue(trimmed) {
            info.availableCPUs = v
        }
    }
    return info
}

private func parseValue(_ line: String) -> Int? {
    let parts = line.components(separatedBy: "=")
    guard parts.count == 2 else { return nil }
    return Int(parts[1].trimmingCharacters(in: .whitespaces))
}

func runCommand(_ path: String, args: [String]) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

// Nominal CPU frequency via sysctl (not real-time, just for reference)
func nominalCPUFreqGHz() -> Double? {
    var freq: Int64 = 0
    var size = MemoryLayout<Int64>.size
    let r = sysctlbyname("hw.cpufrequency", &freq, &size, nil, 0)
    guard r == 0, freq > 0 else { return nil }
    return Double(freq) / 1_000_000_000.0
}
