import AppKit
import Combine
import Foundation

@MainActor
final class SessionController: ObservableObject {
    enum Phase: String {
        case idle
        case working
        case onBreak
    }

    typealias BlockerFactory = @MainActor (SessionController) -> BreakBlocking
    typealias ForegroundProvider = () -> String?

    @Published var phase: Phase = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var isPaused: Bool = false

    @Published var workMinutes: Int {
        didSet { defaults.set(workMinutes, forKey: Keys.workMinutes) }
    }
    @Published var breakMinutes: Int {
        didSet { defaults.set(breakMinutes, forKey: Keys.breakMinutes) }
    }
    @Published var allowSkip: Bool {
        didSet { defaults.set(allowSkip, forKey: Keys.allowSkip) }
    }
    @Published var bypassBundleIDs: Set<String> {
        didSet { defaults.set(Array(bypassBundleIDs), forKey: Keys.bypassBundleIDs) }
    }

    private enum Keys {
        static let workMinutes = "workMinutes"
        static let breakMinutes = "breakMinutes"
        static let allowSkip = "allowSkip"
        static let bypassBundleIDs = "bypassBundleIDs"
    }

    private let defaults: UserDefaults
    private let blockerFactory: BlockerFactory
    private let foregroundBundleIDProvider: ForegroundProvider

    private var timer: Timer?
    private(set) var phaseEndDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private var blocker: BreakBlocking?

    init(
        defaults: UserDefaults = .standard,
        blockerFactory: @escaping BlockerFactory = { @MainActor controller in
            BlockerCoordinator(controller: controller)
        },
        foregroundBundleIDProvider: @escaping ForegroundProvider = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.defaults = defaults
        self.blockerFactory = blockerFactory
        self.foregroundBundleIDProvider = foregroundBundleIDProvider

        defaults.register(defaults: [
            Keys.workMinutes: 50,
            Keys.breakMinutes: 10,
            Keys.allowSkip: true,
            Keys.bypassBundleIDs: [String]()
        ])
        self.workMinutes = defaults.integer(forKey: Keys.workMinutes)
        self.breakMinutes = defaults.integer(forKey: Keys.breakMinutes)
        self.allowSkip = defaults.bool(forKey: Keys.allowSkip)
        let saved = defaults.array(forKey: Keys.bypassBundleIDs) as? [String] ?? []
        self.bypassBundleIDs = Set(saved)
    }

    func startWork() {
        beginPhase(.working, duration: TimeInterval(workMinutes * 60))
    }

    func startBreak() {
        beginPhase(.onBreak, duration: TimeInterval(breakMinutes * 60))
    }

    func testBreak(seconds: TimeInterval = 10) {
        beginPhase(.onBreak, duration: seconds)
    }

    func skipBreak() {
        guard phase == .onBreak, allowSkip else { return }
        finishBreak()
    }

    func pause() {
        guard !isPaused, phase != .idle else { return }
        timer?.invalidate()
        timer = nil
        pausedRemaining = timeRemaining
        phaseEndDate = nil
        isPaused = true
    }

    func resume() {
        guard isPaused, let remaining = pausedRemaining else { return }
        isPaused = false
        pausedRemaining = nil
        phaseEndDate = Date().addingTimeInterval(remaining)
        startTickTimer()
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    func liveRemaining(at date: Date = Date()) -> TimeInterval {
        if isPaused, let r = pausedRemaining { return max(0, r) }
        if let end = phaseEndDate { return max(0, end.timeIntervalSince(date)) }
        return max(0, timeRemaining)
    }

    func liveElapsedProgress(at date: Date = Date()) -> Double {
        guard totalDuration > 0 else { return 0 }
        return min(1, max(0, 1 - liveRemaining(at: date) / totalDuration))
    }

    private func beginPhase(_ newPhase: Phase, duration: TimeInterval) {
        timer?.invalidate()
        timer = nil
        isPaused = false
        pausedRemaining = nil

        blocker?.hide()
        blocker = nil

        phase = newPhase
        totalDuration = duration
        timeRemaining = duration
        phaseEndDate = Date().addingTimeInterval(duration)

        if newPhase == .onBreak {
            let coord = blockerFactory(self)
            coord.show()
            blocker = coord
        }

        startTickTimer()
    }

    private func startTickTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let end = phaseEndDate else { return }
        let remaining = end.timeIntervalSinceNow
        timeRemaining = max(0, remaining)
        if remaining <= 0 {
            switch phase {
            case .working: finishWork()
            case .onBreak: finishBreak()
            case .idle: break
            }
        }
    }

    private func finishWork() {
        timer?.invalidate()
        timer = nil
        if isForegroundAppBypassed() {
            startWork()
        } else {
            startBreak()
        }
    }

    private func finishBreak() {
        timer?.invalidate()
        timer = nil
        blocker?.hide()
        blocker = nil
        startWork()
    }

    private func isForegroundAppBypassed() -> Bool {
        guard let id = foregroundBundleIDProvider() else { return false }
        return bypassBundleIDs.contains(id)
    }

    func _expirePhaseForTesting() {
        phaseEndDate = Date().addingTimeInterval(-1)
        tick()
    }
}
