import Foundation

/// Bound UI progress traffic while retaining the first and final update.
struct NextProgressThrottle {
    private var lastEmission: TimeInterval?
    private let interval: TimeInterval
    init(interval: TimeInterval = 0.2) { self.interval = interval }
    mutating func shouldEmit(at time: TimeInterval, completed: Bool = false) -> Bool {
        guard completed || lastEmission == nil || time - (lastEmission ?? time) >= interval else { return false }
        lastEmission = time
        return true
    }
}
