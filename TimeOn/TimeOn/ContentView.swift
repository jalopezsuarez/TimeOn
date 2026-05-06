import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: SessionController

    @State private var showAppPicker = false
    @State private var runningApps: [RunningApp] = []

    private let workOptions = [25, 30, 45, 50, 60, 75, 90, 120]
    private let breakOptions = [1, 5, 10, 15, 20, 30, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusCard
            settingsForm
            bypassSection
            actionsRow
            Divider()
            quitRow
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("TimeOn")
                    .font(.headline)
                Text("Forced breaks for healthier sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 8, height: 8)
                Text(phaseLabel)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(timeString)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(phaseColor)
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var settingsForm: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Work duration")
                Spacer()
                Picker("", selection: $controller.workMinutes) {
                    ForEach(workOptions, id: \.self) { m in
                        Text("\(m) min").tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Text("Break duration")
                Spacer()
                Picker("", selection: $controller.breakMinutes) {
                    ForEach(breakOptions, id: \.self) { m in
                        Text("\(m) min").tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show \"Skip Break\" button")
                        .font(.callout)
                    Text("When off, you must wait the break out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $controller.allowSkip)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bypassSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showAppPicker.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showAppPicker ? 90 : 0))
                    Text("Skip break when foreground app is…")
                        .font(.callout)
                    Spacer()
                    if !controller.bypassBundleIDs.isEmpty {
                        Text("\(controller.bypassBundleIDs.count)")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAppPicker {
                appPicker
                    .padding(.top, 8)
            }
        }
        .onChange(of: showAppPicker) { _, expanded in
            if expanded { refreshRunningApps() }
        }
    }

    private var appPicker: some View {
        VStack(spacing: 6) {
            if runningApps.isEmpty {
                Text("No applications detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(runningApps) { app in
                            appRow(app)
                            if app.id != runningApps.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button {
                    refreshRunningApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                if !controller.bypassBundleIDs.isEmpty {
                    Button("Clear all") {
                        controller.bypassBundleIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func appRow(_ app: RunningApp) -> some View {
        let isSelected = controller.bypassBundleIDs.contains(app.bundleID)
        return Button {
            if isSelected {
                controller.bypassBundleIDs.remove(app.bundleID)
            } else {
                controller.bypassBundleIDs.insert(app.bundleID)
            }
        } label: {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app")
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                }
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var actionsRow: some View {
        HStack(spacing: 6) {
            Button {
                controller.testBreak(seconds: 10)
            } label: {
                Label("Test", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                controller.togglePause()
            } label: {
                Label(
                    controller.isPaused ? "Resume" : "Pause",
                    systemImage: controller.isPaused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(controller.phase == .idle)

            Button {
                controller.startWork()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var quitRow: some View {
        HStack {
            Spacer()
            Button("Quit TimeOn") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    private func refreshRunningApps() {
        runningApps = RunningAppsProvider.snapshot()
    }

    private var phaseColor: Color {
        if controller.isPaused { return .yellow }
        switch controller.phase {
        case .idle: return .secondary
        case .working: return .green
        case .onBreak: return .orange
        }
    }

    private var phaseLabel: String {
        if controller.isPaused {
            switch controller.phase {
            case .working: return "Paused (work)"
            case .onBreak: return "Paused (break)"
            case .idle: return "Idle"
            }
        }
        switch controller.phase {
        case .idle: return "Idle"
        case .working: return "Working"
        case .onBreak: return "On Break"
        }
    }

    private var timeString: String {
        let total = Int(controller.timeRemaining.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private var progress: Double {
        guard controller.totalDuration > 0 else { return 0 }
        return min(1, max(0, 1 - controller.timeRemaining / controller.totalDuration))
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionController())
        .frame(width: 380)
}
