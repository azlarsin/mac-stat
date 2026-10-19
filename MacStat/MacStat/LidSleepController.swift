import Foundation
import IOKit
import IOKit.pwr_mgt
import Darwin

/// Keeps the global clamshell override in a child process. EOF on its control
/// pipe restores sleep even when the menu bar app crashes or is force-quit.
final class LidSleepController {
    static let helperArgument = "--macstat-lid-sleep-helper"

    var onFailure: (() -> Void)?
    private var process: Process?
    private var control: FileHandle?
    private var enabled = false
    private let restoreSleep: () -> Void

    init(restoreSleep: @escaping () -> Void = { LidSleepController.restoreSleep() }) {
        self.restoreSleep = restoreSleep
    }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled || process != nil else { return }
        if process == nil {
            let pipe = Pipe()
            let child = Process()
            child.executableURL = Bundle.main.executableURL
            child.arguments = [Self.helperArgument]
            child.standardInput = pipe
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                DispatchQueue.main.async {
                    guard let self, self.process === child else { return }
                    self.process = nil
                    try? self.control?.close()
                    self.control = nil
                    // The kernel does not associate the flag with a process.
                    // Recover it here if the helper itself was interrupted.
                    if self.enabled && child.terminationReason == .uncaughtSignal {
                        self.restoreSleep()
                    }
                    self.enabled = false
                    self.onFailure?()
                }
            }
            // A failed child must produce a Swift error, not SIGPIPE in the app.
            guard fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                throw CocoaError(.fileWriteUnknown)
            }
            try child.run()
            process = child
            control = pipe.fileHandleForWriting
            try? pipe.fileHandleForReading.close()
        }
        // Reapply immediately on power-source notifications, even if both
        // sources allow lid-closed mode; powerd can have reset the flag.
        guard enabled || self.enabled != enabled else { return }
        try control?.write(contentsOf: Data([enabled ? 1 : 0]))
        self.enabled = enabled
    }

    func stop() {
        // Do not terminate the helper: it must first clear the kernel flag.
        try? control?.close()
        control = nil
        process = nil
        enabled = false
    }

    deinit { stop() }

    static func runHelper() -> Int32 {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return 1 }
        defer { IOObjectRelease(service) }
        // This property is absent on Macs without a lid.
        guard IORegistryEntryCreateCFProperty(service, kAppleClamshellStateKey as CFString,
                                              kCFAllocatorDefault, 0)?.takeRetainedValue() != nil else { return 1 }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return 1 }
        defer { IOServiceClose(connection) }
        return runHelper(input: .standardInput) { disabled in
            setSleepDisabled(disabled, connection: connection)
        }
    }

    // Internal entry point also permits lifecycle tests without changing power policy.
    static func runHelper(input: FileHandle, setSleepDisabled: (Bool) -> Bool) -> Int32 {
        var disabled = false
        defer {
            if disabled { _ = setSleepDisabled(false) }
        }
        var descriptor = pollfd(fd: input.fileDescriptor, events: Int16(POLLIN), revents: 0)
        while true {
            // powerd may reset the override during wake or power-source changes.
            let result = poll(&descriptor, 1, disabled ? 1_000 : -1)
            if result < 0 {
                if errno == EINTR { continue }
                return 1
            }
            if result > 0 {
                guard descriptor.revents & Int16(POLLNVAL) == 0 else { return 1 }
                // Read only the bytes already available. FileHandle's buffered
                // read(upToCount:) can wait for more commands and delay enable.
                var commands = [UInt8](repeating: 0, count: 256)
                let count = Darwin.read(input.fileDescriptor, &commands, commands.count)
                if count < 0 {
                    if errno == EINTR { continue }
                    return 1
                }
                if count == 0 { return 0 }
                let requested = commands[count - 1] != 0
                if requested || disabled {
                    guard setSleepDisabled(requested) else { return 1 }
                }
                disabled = requested
            } else if disabled, !setSleepDisabled(true) {
                return 1
            }
        }
    }

    private static func setSleepDisabled(_ disabled: Bool, connection: io_connect_t) -> Bool {
        // IOPMLibDefs.h / XNU RootDomainUserClient: kPMSetClamshellSleepState.
        // This is an undocumented interface; callers must handle rejection.
        var value: UInt64 = disabled ? 1 : 0
        return IOConnectCallScalarMethod(connection, UInt32(kPMSetClamshellSleepState),
                                         &value, 1, nil, nil) == KERN_SUCCESS
    }

    private static func restoreSleep() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connection) }
        _ = setSleepDisabled(false, connection: connection)
    }
}
