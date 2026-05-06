import AppKit
import Foundation

struct RunningApp: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: NSImage?

    var bundleID: String { id }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
enum RunningAppsProvider {
    static func snapshot() -> [RunningApp] {
        let selfBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != selfBundleID else { return nil }
                let name = app.localizedName ?? id
                return RunningApp(id: id, name: name, icon: app.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
