import Foundation

struct SystemDateProvider: DateProvider {
    func currentDate() -> Date { Date() }
}
