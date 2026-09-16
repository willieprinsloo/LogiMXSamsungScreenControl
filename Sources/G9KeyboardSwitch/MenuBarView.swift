import SwiftUI
import G9Core

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // Status header (disabled items act as labels in a menu).
        Text("G9 Keyboard Switch").font(.headline)
        Text("Keyboard: \(model.keyboardStatus)")
        Text("Monitor: \(model.monitorName)")
        Text("Last requested input: \(model.lastRequestedInput)")
        Text("Status: \(model.automationStatus)")

        Divider()

        Button("Switch to Mac") { model.switchToMac() }
        Button("Switch to Windows") { model.switchToWindows() }

        Divider()

        Text("Automation")
        Toggle("Manual", isOn: modeBinding(.manual))
        Toggle("Follow to Windows", isOn: modeBinding(.followToWindows))
        Toggle("Return to Mac", isOn: modeBinding(.returnToMac))
        Toggle("Follow both ways", isOn: modeBinding(.followBoth))
        Text("Both directions are DDC writes (Windows = HDMI 1, Mac = HDMI 2).")
            .font(.footnote)
            .foregroundStyle(.secondary)

        if model.isPaused {
            Button("Resume automation") { model.resumeAutomation() }
        } else {
            Button("Pause automation") { model.pauseAutomation() }
        }

        Divider()

        if !model.helperAvailable {
            Text("⚠︎ Display helper (m1ddc) not found")
        }
        if let note = model.lastRecoveryNote {
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }

        Button("Quit") { model.quit() }
            .keyboardShortcut("q")
    }

    /// Radio-style binding: checked when this mode is active; selecting it sets
    /// the mode. Rendered as a flat, checkmarked item in the main menu.
    private func modeBinding(_ m: AutomationMode) -> Binding<Bool> {
        Binding(
            get: { model.mode == m },
            set: { if $0 { model.mode = m } }
        )
    }
}
