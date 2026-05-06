import Foundation

@MainActor
protocol BreakBlocking: AnyObject {
    func show()
    func hide()
}
