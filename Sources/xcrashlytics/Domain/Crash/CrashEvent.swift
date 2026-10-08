import Foundation

struct CrashEvent: Sendable, Hashable {
    /// Canonical CLI id: `XC-<incident>` or `FB-<issue>/events/<event>`.
    var id: String
    var providerId: String?
    var source: CrashSource
    var bundleId: String?
    var bundleVersion: String?
    var osVersion: String?
    var deviceModel: String?
    var crashedThreadIndex: Int
    var exception: ExceptionDescriptor
    var frames: [StackFrame]
    var binaryImages: [BinaryImage]
    var timestamp: Date?
    var rawPath: String?

    init(
        id: String,
        providerId: String? = nil,
        source: CrashSource,
        bundleId: String? = nil,
        bundleVersion: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        crashedThreadIndex: Int,
        exception: ExceptionDescriptor,
        frames: [StackFrame],
        binaryImages: [BinaryImage] = [],
        timestamp: Date? = nil,
        rawPath: String? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.source = source
        self.bundleId = bundleId
        self.bundleVersion = bundleVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.crashedThreadIndex = crashedThreadIndex
        self.exception = exception
        self.frames = frames
        self.binaryImages = binaryImages
        self.timestamp = timestamp
        self.rawPath = rawPath
    }
}
