#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class RelayMenuBarController {
    static let shared = RelayMenuBarController()

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private let baseImage: NSImage

    private init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        baseImage = RelayMenuBarController.makeMenuBarImage()
        configureButton()
        configurePopover()
        observeSnapshot()
        updateButtonAppearance(for: RelayControlCenter.shared.snapshot)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imageScaling = .scaleProportionallyUpOrDown
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.image = baseImage
        button.imagePosition = .imageOnly
        button.toolTip = "Noema Relay"
        button.appearsDisabled = false
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 240)
        popover.contentViewController = NSHostingController(rootView: RelayMenuBarView(
            onToggle: { [weak self] in self?.toggleRelay() },
            onOpenConsole: { [weak self] in self?.openRelayConsole() },
            onQuit: { NSApp.terminate(nil) }
        ))
    }

    private func observeSnapshot() {
        cancellable = RelayControlCenter.shared.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateButtonAppearance(for: snapshot)
            }
    }

    private func updateButtonAppearance(for snapshot: RelayControlCenter.Snapshot) {
        guard let button = statusItem.button else { return }
        let tint: NSColor?
        if snapshot.isRunning {
            tint = NSColor.systemBlue
        } else if snapshot.isStarting || snapshot.isLANStarting {
            tint = NSColor.systemOrange
        } else {
            tint = nil
        }
        button.image = baseImage
        button.contentTintColor = tint
        button.toolTip = snapshot.statusMessage
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                configurePopoverWindow(window)
                window.makeKey()
            }
        }
    }

    private func configurePopoverWindow(_ window: NSWindow) {
        window.styleMask.remove([.titled, .closable, .miniaturizable, .resizable])
        window.styleMask.insert(.borderless)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.fullScreenButton)?.isHidden = true
    }

    private func toggleRelay() {
        let snapshot = RelayControlCenter.shared.snapshot
        if snapshot.isRunning || snapshot.isStarting {
            RelayControlCenter.shared.stopRelay()
        } else {
            RelayControlCenter.shared.startRelay()
        }
    }

    private func openRelayConsole() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.arrangeInFront(nil)
        }
    }
}

private struct RelayMenuBarView: View {
    @ObservedObject private var controlCenter = RelayControlCenter.shared

    let onToggle: () -> Void
    let onOpenConsole: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let snapshot = controlCenter.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Noema Relay")
                        .font(.headline)
                    Text(snapshot.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                stateBadge(for: snapshot)
            }

            if let lan = snapshot.lanAddress, !lan.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reachable at")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(lan)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(lan, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy local URL")
                    }
                }
            }

            Button(action: onToggle) {
                HStack {
                    Image(systemName: snapshot.isRunning ? "pause.fill" : "play.fill")
                    Text(snapshot.isRunning ? "Stop Relay" : "Start Relay")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!RelayControlCenter.shared.hasDelegate || snapshot.isLANStarting)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    onOpenConsole()
                } label: {
                    Label("Open Relay Console…", systemImage: "rectangle.and.text.magnifyingglass")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    onQuit()
                } label: {
                    Label("Quit Noema", systemImage: "power")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 268)
    }

    @ViewBuilder
    private func stateBadge(for snapshot: RelayControlCenter.Snapshot) -> some View {
        let info: (String, String, Color) = {
            if snapshot.isRunning {
                return ("checkmark.circle.fill", "Running", .green)
            }
            if snapshot.isStarting || snapshot.isLANStarting {
                return ("clock.arrow.2.circlepath", "Starting…", .orange)
            }
            return ("pause.circle", "Stopped", Color.secondary)
        }()
        let (symbol, text, tint) = info
        Label {
            Text(text)
                .font(.caption)
        } icon: {
            Image(systemName: symbol)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule(style: .continuous))
        .foregroundColor(tint)
    }
}

private extension RelayMenuBarController {
    static func makeMenuBarImage() -> NSImage {
        if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Noema Relay") {
            symbol.isTemplate = true
            return symbol
        }
        return NSImage()
    }
}
#endif
