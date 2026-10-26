import Foundation

struct NextTransferSnapshot: Equatable, Sendable {
    let received: Int64
    let expected: Int64
    var fraction: Double? {
        guard expected > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(expected)))
    }
    var percent: Int? { fraction.map { Int($0 * 100) } }
    var bytesText: String {
        let actual = ByteCountFormatter.string(fromByteCount: max(0, received), countStyle: .file)
        guard expected > 0 else { return actual }
        return actual + " / " + ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
    }
    var notificationText: String {
        guard let percent else { return "جاري التنزيل\n" + bytesText }
        // Text progress, as in the reference; it always represents measured bytes.
        let filled = min(10, max(0, percent / 10))
        let meter = String(repeating: "▰", count: filled) + String(repeating: "▱", count: 10 - filled)
        return "جاري التنزيل (\(percent)٪)\n\(meter)\n\(bytesText)"
    }
}
