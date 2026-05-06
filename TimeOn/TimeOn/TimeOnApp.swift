import SwiftUI

@main
struct TimeOnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appDelegate.controller)
                .frame(width: 380)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var controller: SessionController

    var body: some View {
        Text(text)
            .monospacedDigit()
    }

    private var text: String {
        let minutes = max(0, Int(ceil(controller.timeRemaining / 60)))
        if controller.isPaused {
            return "⏸ \(minutes)m"
        }
        switch controller.phase {
        case .idle:    return "⦿ --"
        case .working: return "⦿ \(minutes)m"
        case .onBreak: return "⦿ \(minutes)m"
        }
    }
}
