import Foundation

struct CrashEventPayload: Encodable, Sendable {
    var id: String
    var providerId: String?
    var source: String
    var bundleId: String?
    var bundleVersion: String?
    var osVersion: String?
    var deviceModel: String?
    var crashedThreadIndex: Int
    var exception: ExceptionDescriptorPayload
    var frames: [StackFramePayload]
    var binaryImages: [BinaryImagePayload]
    var timestamp: Date?
    var rawPath: String?

    init(_ event: CrashEvent) {
        id = event.id
        providerId = event.providerId
        source = event.source.rawValue
        bundleId = event.bundleId
        bundleVersion = event.bundleVersion
        osVersion = event.osVersion
        deviceModel = event.deviceModel
        crashedThreadIndex = event.crashedThreadIndex
        exception = ExceptionDescriptorPayload(event.exception)
        frames = event.frames.map(StackFramePayload.init)
        binaryImages = event.binaryImages.map(BinaryImagePayload.init)
        timestamp = event.timestamp
        rawPath = event.rawPath
    }
}

struct StackFramePayload: Encodable, Sendable {
    var index: Int
    var binaryName: String
    var symbol: String?
    var file: String?
    var line: Int?
    var column: Int?
    var address: UInt64?
    var imageUUID: String?
    var isSymbolicated: Bool
    var firebaseSymbol: String?
    var symbolicated: String?

    init(_ frame: StackFrame) {
        index = frame.index
        binaryName = frame.binaryName
        symbol = frame.symbol
        file = frame.file
        line = frame.line
        column = frame.column
        address = frame.address
        imageUUID = frame.imageUUID
        isSymbolicated = frame.isSymbolicated
        firebaseSymbol = frame.firebaseSymbol
        symbolicated = frame.symbolicated
    }
}

struct ExceptionDescriptorPayload: Encodable, Sendable {
    var exceptionType: String
    var signal: String?
    var subtype: String?
    var description: String?

    init(_ exception: ExceptionDescriptor) {
        exceptionType = exception.exceptionType
        signal = exception.signal
        subtype = exception.subtype
        description = exception.description
    }
}

struct BinaryImagePayload: Encodable, Sendable {
    var name: String
    var uuid: String
    var loadAddress: UInt64
    var arch: String
    var path: String

    init(_ image: BinaryImage) {
        name = image.name
        uuid = image.uuid
        loadAddress = image.loadAddress
        arch = image.arch
        path = image.path
    }
}
