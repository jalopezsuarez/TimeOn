import SwiftUI

struct BreakBlockerView: View {
    @EnvironmentObject var controller: SessionController

    private static let foreground = Color(red: 0x71 / 255, green: 0x71 / 255, blue: 0x71 / 255)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let barWidth = min(max(geo.size.width * 0.25, 160), 360)

                VStack {
                    Spacer()

                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                        let remaining = controller.liveRemaining(at: context.date)
                        let progress = controller.liveElapsedProgress(at: context.date)
                        let elapsed = max(0, controller.totalDuration - remaining)

                        VStack(spacing: 14) {
                            SmoothProgressBar(progress: progress, color: Self.foreground)
                                .frame(width: barWidth, height: 7)

                            HStack {
                                Text(elapsedLabel(elapsed))
                                    .foregroundStyle(Self.foreground)
                                Spacer()
                                Text(remainingLabel(remaining))
                                    .foregroundStyle(Self.foreground)
                            }
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .frame(width: barWidth)

                            if controller.allowSkip {
                                Button(action: { controller.skipBreak() }) {
                                    Text("Skip Break")
                                        .font(.system(size: 13, weight: .medium))
                                        .padding(.horizontal, 22)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Self.foreground)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Self.foreground, lineWidth: 1)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, 64)
                }
            }
        }
    }

    private func elapsedLabel(_ t: TimeInterval) -> String {
        format(t)
    }

    private func remainingLabel(_ t: TimeInterval) -> String {
        "-" + format(t)
    }

    private func format(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

private struct SmoothProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
    }
}
