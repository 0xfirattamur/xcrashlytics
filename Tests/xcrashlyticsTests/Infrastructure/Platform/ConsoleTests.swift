import Darwin
import Foundation
import Testing
@testable import xcrashlytics

@Suite("console")
struct ConsoleTests {
    @Test("writing to a closed pipe reports failure instead of killing the process")
    func closedPipeDoesNotKillProcess() throws {
        StandardStreamConsole.ignoreBrokenPipeSignal()
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        close(fds[0])
        #expect(FileDescriptorWriter.write("payload\n", to: fds[1]) == false)
        close(fds[1])
    }

    @Test("writing to an open pipe delivers every byte, including past the pipe buffer")
    func writesEverything() throws {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        // Keep concurrently spawned test subprocesses from inheriting the write end, which would withhold EOF.
        _ = fcntl(fds[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(fds[1], F_SETFD, FD_CLOEXEC)
        let text = String(repeating: "é", count: 100_000)
        let reader = Thread {
            var total = 0
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(fds[0], &buffer, buffer.count)
                if count <= 0 { break }
                total += count
            }
            close(fds[0])
            expectedBytesRead.withLock { $0 = total }
        }
        reader.start()
        #expect(FileDescriptorWriter.write(text, to: fds[1]))
        close(fds[1])
        while !reader.isFinished { usleep(1_000) }
        #expect(expectedBytesRead.withLock { $0 } == text.utf8.count)
    }
}

private let expectedBytesRead = LockedBox(0)

private final class LockedBox: @unchecked Sendable {
    private var value: Int
    private let lock = NSLock()
    init(_ value: Int) { self.value = value }
    func withLock<T>(_ body: (inout Int) -> T) -> T { lock.withLock { body(&value) } }
}
