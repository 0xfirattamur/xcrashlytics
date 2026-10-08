import CryptoKit
import Foundation

enum SHA256Hasher {
    static func hexDigest(of value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
