import Foundation
import Darwin
import IOKit
import IOKit.ps

struct MemoryInfo {
    var totalGB: Double
    var usedGB: Double
    var freeGB: Double
    var usedPercent: Int
}

struct CPUUsage {
    var userPercent: Double
    var systemPercent: Double
    var idlePercent: Double
    var totalPercent: Double { userPercent + systemPercent }
}

struct NetworkThroughput {
    var rxBytesPerSec: Int64
    var txBytesPerSec: Int64
}

struct DiskUsage {
    var totalGB: Double
    var usedGB: Double
    var freeGB: Double
    var usedPercent: Int
}

struct BatteryInfo {
    var percent: Int
    var isCharging: Bool
}

struct DiskIOStats {
    var readBytesPerSec: Int64
    var writeBytesPerSec: Int64
}

// MARK: Memory

func readMemoryInfo() -> MemoryInfo? {
    var vmStats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &vmStats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }

    let pageSize = Int64(vm_page_size)
    var totalMem: Int64 = 0
    var size = MemoryLayout<Int64>.size
    sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)

    let active   = Int64(vmStats.active_count)   * pageSize
    let wired    = Int64(vmStats.wire_count)      * pageSize
    let compressed = Int64(vmStats.compressor_page_count) * pageSize
    let used     = active + wired + compressed
    let free     = totalMem - used
    let totalGB  = Double(totalMem) / 1_073_741_824
    let usedGB   = Double(used) / 1_073_741_824
    let freeGB   = Double(free) / 1_073_741_824
    let pct      = totalMem > 0 ? Int(Double(used) / Double(totalMem) * 100) : 0
    return MemoryInfo(totalGB: totalGB, usedGB: usedGB, freeGB: freeGB, usedPercent: pct)
}

// MARK: CPU Usage (delta between two calls)

private var prevCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64, total: UInt64) = (0, 0, 0, 0)

func readCPUUsage() -> CPUUsage? {
    var numCPU: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var numInfo: mach_msg_type_number_t = 0
    let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &cpuInfo, &numInfo)
    guard kr == KERN_SUCCESS, let info = cpuInfo else { return nil }
    defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(numInfo) * vm_size_t(MemoryLayout<integer_t>.size)) }

    var user: UInt64 = 0, sys: UInt64 = 0, idle: UInt64 = 0
    let stride = Int(CPU_STATE_MAX)
    for i in 0..<Int(numCPU) {
        user += UInt64(bitPattern: Int64(info[i * stride + Int(CPU_STATE_USER)]))
        sys  += UInt64(bitPattern: Int64(info[i * stride + Int(CPU_STATE_SYSTEM)]))
        idle += UInt64(bitPattern: Int64(info[i * stride + Int(CPU_STATE_IDLE)]))
             + UInt64(bitPattern: Int64(info[i * stride + Int(CPU_STATE_NICE)]))
    }
    let total = user + sys + idle

    let dUser  = user  - prevCPUTicks.user
    let dSys   = sys   - prevCPUTicks.sys
    let dIdle  = idle  - prevCPUTicks.idle
    let dTotal = total - prevCPUTicks.total
    prevCPUTicks = (user, sys, idle, total)
    guard dTotal > 0 else { return nil }

    return CPUUsage(
        userPercent:   Double(dUser)  / Double(dTotal) * 100,
        systemPercent: Double(dSys)   / Double(dTotal) * 100,
        idlePercent:   Double(dIdle)  / Double(dTotal) * 100
    )
}

// MARK: Network (per-second throughput via two successive reads with a 1s interval)

private var prevNetBytes: (rx: Int64, tx: Int64, time: TimeInterval) = (0, 0, 0)

func readNetworkThroughput() -> NetworkThroughput? {
    var ifaddrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrs) == 0, let first = ifaddrs else { return nil }
    defer { freeifaddrs(first) }

    var rx: Int64 = 0, tx: Int64 = 0
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let cur = cursor {
        let addr = cur.pointee
        if addr.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
            if let data = addr.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += Int64(data.pointee.ifi_ibytes)
                tx += Int64(data.pointee.ifi_obytes)
            }
        }
        cursor = addr.ifa_next
    }

    let now = Date().timeIntervalSince1970
    let dt = now - prevNetBytes.time
    var result: NetworkThroughput? = nil
    if prevNetBytes.time > 0, dt > 0 {
        result = NetworkThroughput(
            rxBytesPerSec: max(0, Int64(Double(rx - prevNetBytes.rx) / dt)),
            txBytesPerSec: max(0, Int64(Double(tx - prevNetBytes.tx) / dt))
        )
    }
    prevNetBytes = (rx, tx, now)
    return result
}

// MARK: Battery

func readBatteryInfo() -> BatteryInfo? {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [AnyObject]
    guard let src = list.first,
          let desc = IOPSGetPowerSourceDescription(snapshot, src).takeUnretainedValue() as? [String: Any],
          let pct = desc[kIOPSCurrentCapacityKey] as? Int
    else { return nil }
    let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
    return BatteryInfo(percent: pct, isCharging: charging)
}

// MARK: Disk IO

private var prevDiskIO: (read: Int64, write: Int64, time: TimeInterval) = (0, 0, 0)

func readDiskIO() -> DiskIOStats? {
    var readBytes: Int64 = 0
    var writeBytes: Int64 = 0

    var iter: io_iterator_t = 0
    let matching = IOServiceMatching("IOBlockStorageDriver")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iter) }

    var obj = IOIteratorNext(iter)
    while obj != 0 {
        defer { IOObjectRelease(obj) }
        var cfProps: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(obj, &cfProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let props = cfProps?.takeRetainedValue() as? [String: Any],
           let stats = props["Statistics"] as? [String: Any] {
            readBytes  += (stats["Bytes (Read)"]  as? NSNumber)?.int64Value ?? 0
            writeBytes += (stats["Bytes (Written)"] as? NSNumber)?.int64Value ?? 0
        }
        obj = IOIteratorNext(iter)
    }

    let now = Date().timeIntervalSince1970
    let dt = now - prevDiskIO.time
    var result: DiskIOStats? = nil
    if prevDiskIO.time > 0, dt > 0 {
        result = DiskIOStats(
            readBytesPerSec:  max(0, Int64(Double(readBytes  - prevDiskIO.read)  / dt)),
            writeBytesPerSec: max(0, Int64(Double(writeBytes - prevDiskIO.write) / dt))
        )
    }
    prevDiskIO = (readBytes, writeBytes, now)
    return result
}

// MARK: Disk

func readDiskUsage() -> DiskUsage? {
    guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
          let total = attrs[.systemSize] as? Int64,
          let free  = attrs[.systemFreeSize] as? Int64 else { return nil }
    let used = total - free
    let pct  = total > 0 ? Int(Double(used) / Double(total) * 100) : 0
    return DiskUsage(
        totalGB: Double(total) / 1_073_741_824,
        usedGB:  Double(used)  / 1_073_741_824,
        freeGB:  Double(free)  / 1_073_741_824,
        usedPercent: pct
    )
}

// MARK: Helpers

func formatBytes(_ bytes: Int64) -> String {
    switch bytes {
    case ..<1024:               return "\(bytes) B/s"
    case ..<(1024*1024):        return String(format: "%.0f KB/s", Double(bytes)/1024)
    case ..<(1024*1024*1024):   return String(format: "%.1f MB/s", Double(bytes)/1_048_576)
    default:                    return String(format: "%.1f GB/s", Double(bytes)/1_073_741_824)
    }
}
