import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let macStatResizePopover = Notification.Name("com.azlar.macstat.resizePopover")
    static let macStatClosePopover  = Notification.Name("com.azlar.macstat.closePopover")
    static let macStatOpenSettings  = Notification.Name("com.azlar.macstat.openSettings")
    static let macStatShowStats     = Notification.Name("com.azlar.macstat.showStats")
}

@main
struct MacStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var model = StatsModel()
    private var cancellables = Set<AnyCancellable>()
    private var hostingController: NSHostingController<AnyView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = #selector(handleButtonClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let hc = NSHostingController(rootView: AnyView(ContentView().environmentObject(model)))
        popover.contentViewController = hc
        hostingController = hc
        self.popover = popover

        model.$menuBarParts
            .receive(on: RunLoop.main)
            .sink { [weak self] parts in
                self?.applyMenuBarParts(parts)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePopoverSize),
            name: .macStatResizePopover,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopoverFromSettings),
            name: .macStatClosePopover,
            object: nil
        )
    }

    func popoverDidClose(_ notification: Notification) {
        model.suppressLabelUpdates = false
        model.menuBarParts = model.buildParts()
        NotificationCenter.default.post(name: .macStatShowStats, object: nil)
    }

    @objc func closePopoverFromSettings() {
        popover?.performClose(nil)
    }

    private func applyMenuBarParts(_ parts: [(symbol: String, text: String)]) {
        guard let button = statusItem?.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .baselineOffset: 0,
        ]

        let result = NSMutableAttributedString()

        // 固定前缀：芯片图标
        if let chipImg = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let att = NSTextAttachment()
            att.image = chipImg
            let s = NSMutableAttributedString(attachment: att)
            s.addAttributes(baseAttrs, range: NSRange(location: 0, length: s.length))
            result.append(s)
        }

        for (i, part) in parts.enumerated() {
            result.append(NSAttributedString(string: "  ", attributes: baseAttrs))
            _ = i  // suppress unused warning
            if let img = NSImage(systemSymbolName: part.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) {
                let attachment = NSTextAttachment()
                attachment.image = img
                let attachStr = NSMutableAttributedString(attachment: attachment)
                attachStr.addAttributes(baseAttrs, range: NSRange(location: 0, length: attachStr.length))
                result.append(attachStr)
                result.append(NSAttributedString(string: "\u{200A}", attributes: baseAttrs))
            }
            result.append(NSAttributedString(string: part.text, attributes: baseAttrs))
        }


        button.image = nil
        button.attributedTitle = result
    }

    @objc func updatePopoverSize() {
        guard let pop = popover, let hc = hostingController else { return }
        hc.view.needsLayout = true
        hc.view.layoutSubtreeIfNeeded()
        let h = hc.view.fittingSize.height
        guard h > 0 else { return }
        pop.contentSize = NSSize(width: 240, height: h)
    }

    @objc func handleButtonClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let pop = popover else { return }
        if pop.isShown {
            pop.performClose(sender)
        } else {
            showPopover()
        }
    }

    // Show the popover and make its window key, so the NSVisualEffectView
    // background renders in its active (vibrant) appearance instead of the
    // washed-out inactive state it shows when the app isn't frontmost.
    private func showPopover() {
        guard let button = statusItem?.button, let pop = popover else { return }
        model.suppressLabelUpdates = true
        updatePopoverSize()
        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About MacStat", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacStat", action: #selector(quitApp), keyEquivalent: "q")
            .target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MacStat"
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        alert.informativeText = "A minimal macOS menubar system monitor.\n\nVersion \(version) (\(build))\nAuthor: azlar\ngithub.com/azlarsin/mac-stat\n© 2026"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.icon = NSApp.applicationIconImage
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openSettings() {
        guard let pop = popover else { return }
        if pop.isShown { pop.performClose(nil) }
        showPopover()
        NotificationCenter.default.post(name: .macStatOpenSettings, object: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
