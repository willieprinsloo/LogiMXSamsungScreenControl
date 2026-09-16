import AppKit
import G9Core

/// Maps NSWorkspace sleep/wake and session lock/unlock notifications to
/// `LifecycleEvent`s. Callbacks are delivered on the main thread. (Concrete,
/// main-actor isolated; the `LifecycleEventSource` protocol in G9Core documents
/// the shape but is not used polymorphically here.)
@MainActor
final class LifecycleMonitor {
    var onEvent: ((LifecycleEvent) -> Void)?

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dc.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func willSleep() { onEvent?(.willSleep) }
    @objc private func didWake() { onEvent?(.didWake) }
    @objc private func screenLocked() { onEvent?(.screensDidLock) }
    @objc private func screenUnlocked() { onEvent?(.screensDidUnlock) }
}
