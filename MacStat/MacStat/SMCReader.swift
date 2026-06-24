import Foundation
import IOKit

// Matches Apple's SMCParamStruct exactly (80 bytes).
// C layout has: 3 bytes trailing padding inside keyInfo sub-struct,
// and 1 byte padding before data32 — Swift omits these without explicit pads.
private struct SMCKeyData {
    var key: UInt32 = 0
    // vers (6 bytes as UInt8 × 6 + UInt16) — Swift pads the tuple to 8 bytes,
    // which happens to coincide with the C layout (6 bytes + 2 bytes alignment padding).
    var vers: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt16) = (0,0,0,0,0,0,0)
    // pLimitData — starts at offset 12 in both C and Swift
    var pLimitVersion: UInt16 = 0
    var pLimitLength: UInt16 = 0
    var pLimitCPU: UInt32 = 0
    var pLimitGPU: UInt32 = 0
    var pLimitMem: UInt32 = 0
    // keyInfo — offset 28
    var keyInfoDataSize: UInt32 = 0
    var keyInfoDataType: UInt32 = 0
    var keyInfoDataAttributes: UInt8 = 0
    // 3 bytes explicit padding (C's keyInfo sub-struct trailing padding)
    var _pad1: UInt8 = 0
    var _pad2: UInt8 = 0
    var _pad3: UInt8 = 0
    // result/status/data8 at offsets 40/41/42
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    // 1 byte explicit padding before data32 (UInt32 alignment, offset 44)
    var _pad4: UInt8 = 0
    var data32: UInt32 = 0
    // bytes[32] at offset 48
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private let kSMCHandleYPCEvent: UInt32 = 2
private let kSMCReadKey: UInt8 = 5
private let kSMCGetKeyInfo: UInt8 = 9

private func fourCC(_ s: String) -> UInt32 {
    s.unicodeScalars.prefix(4).reduce(0) { ($0 << 8) | $1.value }
}

class SMCReader {
    private var conn: io_connect_t = 0
    private(set) var isOpen = false

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard kr == kIOReturnSuccess else { return }
        isOpen = true
    }

    deinit {
        if isOpen { IOServiceClose(conn) }
    }

    private func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        let inSize = MemoryLayout<SMCKeyData>.size
        var outSize = MemoryLayout<SMCKeyData>.size
        let kr = IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, &input, inSize, &output, &outSize)
        return kr == kIOReturnSuccess ? output : nil
    }

    private func readKey(_ key: String) -> SMCKeyData? {
        guard isOpen else { return nil }
        var input = SMCKeyData()
        input.key = fourCC(key)
        input.data8 = kSMCGetKeyInfo
        guard let info = call(&input) else { return nil }

        var input2 = SMCKeyData()
        input2.key = fourCC(key)
        input2.keyInfoDataSize = info.keyInfoDataSize
        input2.data8 = kSMCReadKey
        return call(&input2)
    }

    // SP78: signed fixed-point, 1 sign + 7 integer + 8 fractional bits
    private func sp78(_ d: SMCKeyData) -> Double? {
        let b0 = d.bytes.0, b1 = d.bytes.1
        let v = Double(Int16(bitPattern: UInt16(b0) << 8 | UInt16(b1))) / 256.0
        guard v > 0, v < 150 else { return nil }
        return v
    }

    func cpuTemperature() -> Double? {
        // Apple Silicon (M-series) keys, then Intel fallback
        for key in ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0b", "Tp0A", "Tp0B", "Tp0C",
                    "TC0D", "TC0E", "TC0F", "TC0P", "TC0H"] {
            if let d = readKey(key), let t = sp78(d) { return t }
        }
        return nil
    }

    func gpuTemperature() -> Double? {
        // Apple Silicon (M-series) keys, then Intel fallback
        for key in ["Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0b",
                    "TG0D", "TG0P", "TG0H"] {
            if let d = readKey(key), let t = sp78(d) { return t }
        }
        return nil
    }

    func batteryTemperature() -> Double? {
        for key in ["TB0T", "TB1T", "TB2T", "TB3T"] {
            if let d = readKey(key), let t = sp78(d) { return t }
        }
        return nil
    }

    // FPE2: unsigned fixed-point 14 integer + 2 fractional bits
    private func fpe2(_ d: SMCKeyData) -> Double? {
        let b0 = d.bytes.0, b1 = d.bytes.1
        let v = Double(UInt16(b0) << 8 | UInt16(b1)) / 4.0
        guard v > 0, v < 20000 else { return nil }
        return v
    }

    func fanSpeed(index: Int) -> Double? {
        let key = String(format: "F%dAc", index)
        if let d = readKey(key) { return fpe2(d) }
        return nil
    }

    func fanMaxSpeed(index: Int) -> Double? {
        let key = String(format: "F%dMx", index)
        if let d = readKey(key) { return fpe2(d) }
        return nil
    }

    func fanCount() -> Int {
        for key in ["FNum"] {
            if let d = readKey(key) { return Int(d.bytes.0) }
        }
        return 0
    }
}
