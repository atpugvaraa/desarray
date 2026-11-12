import SwiftUI

@main
struct DesarrayApp: App {
    @State private var session = Session()

    var body: some Scene {
        MenuBarExtra {
            Button(session.isActive ? "Stop Inspecting" : "Start Inspecting") { session.toggle() }
                .keyboardShortcut("d", modifiers: [.option, .shift])
            if let status = session.hotKeyStatus {
                Divider()
                Text(status)
            }
            Divider()
            Button("Quit desarray.") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: session.isActive ? "viewfinder.circle.fill" : "viewfinder")
                .accessibilityLabel(session.isActive ? "desarray, inspecting" : "desarray")
        }
    }
}
