import AppKit
import Foundation
import Testing
@testable import TimeOn

@MainActor
final class SpyBlocker: BreakBlocking {
    var showCount = 0
    var hideCount = 0
    func show() { showCount += 1 }
    func hide() { hideCount += 1 }
}

@MainActor
@Suite("SessionController")
struct SessionControllerTests {

    private static var counter = 0

    private func makeController(
        spy: SpyBlocker? = nil,
        foreground: String? = nil
    ) -> (SessionController, SpyBlocker, UserDefaults) {
        Self.counter += 1
        let suiteName = "TimeOnTests-\(Self.counter)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let blocker = spy ?? SpyBlocker()
        let controller = SessionController(
            defaults: defaults,
            blockerFactory: { _ in blocker },
            foregroundBundleIDProvider: { foreground }
        )
        return (controller, blocker, defaults)
    }

    @Test func defaultsAreSetOnInit() {
        let (c, _, _) = makeController()
        #expect(c.workMinutes == 50)
        #expect(c.breakMinutes == 10)
        #expect(c.allowSkip == true)
        #expect(c.bypassBundleIDs.isEmpty)
        #expect(c.phase == .idle)
    }

    @Test func startWorkInitializesWorkPhase() {
        let (c, _, _) = makeController()
        c.workMinutes = 25
        c.startWork()
        #expect(c.phase == .working)
        #expect(c.totalDuration == 25 * 60)
        #expect(c.timeRemaining > 24 * 60)
    }

    @Test func startBreakShowsBlocker() {
        let (c, spy, _) = makeController()
        c.startBreak()
        #expect(c.phase == .onBreak)
        #expect(spy.showCount == 1)
    }

    @Test func skipBreakHidesBlockerAndStartsWork() {
        let (c, spy, _) = makeController()
        c.allowSkip = true
        c.startBreak()
        c.skipBreak()
        #expect(spy.hideCount == 1)
        #expect(c.phase == .working)
    }

    @Test func skipBreakIgnoredWhenDisabled() {
        let (c, spy, _) = makeController()
        c.allowSkip = false
        c.startBreak()
        c.skipBreak()
        #expect(c.phase == .onBreak)
        #expect(spy.hideCount == 0)
    }

    @Test func pauseFreezesTimeRemaining() async {
        let (c, _, _) = makeController()
        c.workMinutes = 10
        c.startWork()
        c.pause()
        let snapshot = c.timeRemaining
        try? await Task.sleep(nanoseconds: 250_000_000)
        #expect(c.timeRemaining == snapshot)
        #expect(c.isPaused)
        #expect(c.liveRemaining(at: Date()) == snapshot)
    }

    @Test func resumeRestartsCountdown() async {
        let (c, _, _) = makeController()
        c.workMinutes = 1
        c.startWork()
        c.pause()
        let snapshot = c.timeRemaining
        c.resume()
        try? await Task.sleep(nanoseconds: 350_000_000)
        let after = c.liveRemaining(at: Date())
        #expect(after < snapshot)
        #expect(!c.isPaused)
    }

    @Test func togglePauseAlternates() {
        let (c, _, _) = makeController()
        c.startWork()
        #expect(!c.isPaused)
        c.togglePause()
        #expect(c.isPaused)
        c.togglePause()
        #expect(!c.isPaused)
    }

    @Test func pauseIgnoredWhenIdle() {
        let (c, _, _) = makeController()
        c.pause()
        #expect(!c.isPaused)
    }

    @Test func pauseDuringBreakKeepsBlockerShowing() {
        let (c, spy, _) = makeController()
        c.startBreak()
        c.pause()
        #expect(c.isPaused)
        #expect(c.phase == .onBreak)
        #expect(spy.hideCount == 0)
    }

    @Test func bypassSkipsBreakAndStartsNewWork() {
        let (c, spy, _) = makeController(foreground: "com.bypass.app")
        c.bypassBundleIDs = ["com.bypass.app"]
        c.workMinutes = 5
        c.startWork()
        c._expirePhaseForTesting()
        #expect(c.phase == .working)
        #expect(spy.showCount == 0)
    }

    @Test func breakTriggeredWhenForegroundNotBypassed() {
        let (c, spy, _) = makeController(foreground: "com.other.app")
        c.bypassBundleIDs = ["com.bypass.app"]
        c.workMinutes = 5
        c.startWork()
        c._expirePhaseForTesting()
        #expect(c.phase == .onBreak)
        #expect(spy.showCount == 1)
    }

    @Test func breakTriggeredWhenNoForeground() {
        let (c, spy, _) = makeController(foreground: nil)
        c.bypassBundleIDs = ["com.bypass.app"]
        c.workMinutes = 5
        c.startWork()
        c._expirePhaseForTesting()
        #expect(c.phase == .onBreak)
        #expect(spy.showCount == 1)
    }

    @Test func newPhaseHidesPreviousBlocker() {
        let (c, spy, _) = makeController()
        c.startBreak()
        #expect(spy.showCount == 1)
        c.startWork()
        #expect(spy.hideCount == 1)
        #expect(c.phase == .working)
    }

    @Test func bypassBundleIDsArePersisted() {
        let (c, _, defaults) = makeController()
        c.bypassBundleIDs = ["com.example.A", "com.example.B"]
        let saved = defaults.array(forKey: "bypassBundleIDs") as? [String] ?? []
        #expect(Set(saved) == ["com.example.A", "com.example.B"])
    }

    @Test func settingsArePersisted() {
        let (c, _, defaults) = makeController()
        c.workMinutes = 75
        c.breakMinutes = 15
        c.allowSkip = false
        #expect(defaults.integer(forKey: "workMinutes") == 75)
        #expect(defaults.integer(forKey: "breakMinutes") == 15)
        #expect(defaults.bool(forKey: "allowSkip") == false)
    }

    @Test func liveRemainingDecreasesOverTime() {
        let (c, _, _) = makeController()
        c.workMinutes = 10
        c.startWork()
        guard let end = c.phaseEndDate else {
            Issue.record("phaseEndDate should be set after startWork")
            return
        }
        let start = end.addingTimeInterval(-c.totalDuration)
        let r1 = c.liveRemaining(at: start)
        let r2 = c.liveRemaining(at: start.addingTimeInterval(60))
        #expect(abs((r1 - r2) - 60) < 0.01)
    }

    @Test func liveProgressClampedToOne() {
        let (c, _, _) = makeController()
        c.workMinutes = 10
        c.startWork()
        let p = c.liveElapsedProgress(at: Date().addingTimeInterval(10_000))
        #expect(p == 1.0)
    }

    @Test func liveProgressZeroAtStart() {
        let (c, _, _) = makeController()
        c.workMinutes = 10
        c.startWork()
        let p = c.liveElapsedProgress(at: Date())
        #expect(p < 0.01)
    }

    @Test func testBreakUsesShortDurationAndShowsBlocker() {
        let (c, spy, _) = makeController()
        c.testBreak(seconds: 3)
        #expect(c.phase == .onBreak)
        #expect(c.totalDuration == 3)
        #expect(spy.showCount == 1)
    }

    @Test func breakExpiryStartsWorkAndHidesBlocker() {
        let (c, spy, _) = makeController()
        c.testBreak(seconds: 0.5)
        #expect(c.phase == .onBreak)
        c._expirePhaseForTesting()
        #expect(c.phase == .working)
        #expect(spy.hideCount == 1)
    }

    @Test func skipBreakIsNoopOutsideBreak() {
        let (c, spy, _) = makeController()
        c.allowSkip = true
        c.startWork()
        c.skipBreak()
        #expect(c.phase == .working)
        #expect(spy.hideCount == 0)
    }

    @Test func resumeAfterPauseExtendsRemainingByPauseDuration() async {
        let (c, _, _) = makeController()
        c.workMinutes = 1
        c.startWork()
        let beforePause = c.timeRemaining
        c.pause()
        try? await Task.sleep(nanoseconds: 300_000_000)
        c.resume()
        let afterResume = c.liveRemaining(at: Date())
        #expect(abs(afterResume - beforePause) < 0.05)
    }

    @Test func liveRemainingZeroForIdle() {
        let (c, _, _) = makeController()
        #expect(c.liveRemaining(at: Date()) == 0)
        #expect(c.liveElapsedProgress(at: Date()) == 0)
    }

    @Test func breakLoopsAfterFinishWhenForegroundChangesToBypass() {
        var foreground: String? = "com.other.app"
        let suiteName = "TimeOnTests-foreground-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let spy = SpyBlocker()
        let c = SessionController(
            defaults: defaults,
            blockerFactory: { _ in spy },
            foregroundBundleIDProvider: { foreground }
        )
        c.bypassBundleIDs = ["com.bypass.app"]
        c.workMinutes = 5
        c.startWork()
        c._expirePhaseForTesting()
        #expect(c.phase == .onBreak)
        #expect(spy.showCount == 1)

        c.startWork()
        foreground = "com.bypass.app"
        c._expirePhaseForTesting()
        #expect(c.phase == .working)
        #expect(spy.showCount == 1)
    }

    @Test func multiplePausesDoNotMutateState() {
        let (c, _, _) = makeController()
        c.startWork()
        c.pause()
        let firstSnapshot = c.timeRemaining
        c.pause()
        c.pause()
        #expect(c.isPaused)
        #expect(c.timeRemaining == firstSnapshot)
    }

    @Test func resumeIsNoopWhenNotPaused() {
        let (c, _, _) = makeController()
        c.startWork()
        let before = c.timeRemaining
        c.resume()
        #expect(!c.isPaused)
        #expect(c.timeRemaining == before)
    }
}
