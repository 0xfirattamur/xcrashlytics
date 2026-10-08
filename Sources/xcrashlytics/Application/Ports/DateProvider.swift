import Foundation

protocol DateProvider: Sendable {
    func currentDate() -> Date
}
