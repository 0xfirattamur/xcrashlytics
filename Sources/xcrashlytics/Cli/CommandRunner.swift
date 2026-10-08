import ArgumentParser
import Foundation

/// Every failure leaves through the error contract: mapped to a code, written in the command's format.
struct CommandRunner: Sendable {
    let presenter: FailurePresenter

    init(console: Console) {
        presenter = FailurePresenter(console: console)
    }

    func run(format: OutputFormat, _ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch let cleanExit as CleanExit {
            throw cleanExit
        } catch {
            throw report(error, format: format)
        }
    }

    func report(_ error: Error, format: OutputFormat) -> ExitCode {
        let failure = Self.failure(for: error)
        presenter.present(failure, format: format)
        return ExitCode(failure.exitCode)
    }

    /// `ValidationError` comes from option checks in commands; it maps to the same BAD_INPUT
    /// as the services' `InvalidInputError`.
    static func failure(for error: Error) -> CommandFailure {
        if let error = error as? ValidationError {
            return CommandFailure(code: "BAD_INPUT", exitCode: 5, message: error.message, hint: nil)
        }
        return FailureMapper.failure(for: error)
    }
}
