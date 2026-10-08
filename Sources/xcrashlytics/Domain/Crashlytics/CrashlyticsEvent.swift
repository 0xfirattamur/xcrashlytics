import Foundation

/// The flattened domain shape of an event; wire quirks stay in `CrashlyticsDTO`.
struct CrashlyticsEvent: Sendable, Equatable {
    var eventId: String?
    // Crashlytics quirk: last segment of the resource name (`<session>_<eventId>`), which is
    // what the console's `sessionEventKey` carries.
    var resourceName: String?
    var issueId: String?
    var issueTitle: String?
    var issueSubtitle: String?
    var eventTime: String?
    var platform: String?
    var bundleOrPackage: String?
    var processState: String?
    var displayVersion: String?
    var buildVersion: String?
    var deviceModel: String?
    var deviceOrientation: String?
    var osVersion: String?
    var osOrientation: String?
    var jailbroken: Bool?
    var memoryFree: Int?
    var memoryUsed: Int?
    var storageFree: Int?
    var storageUsed: Int?
    var userId: String?
    var blameFrame: CrashlyticsFrame?
    var exceptions: [CrashlyticsException]
    var threads: [CrashlyticsThread]
    // Crashlytics quirk: Apple non-fatals arrive in `errors[]`, each with its own stack.
    var errors: [CrashlyticsException]
    var customKeys: [String: String]
    var logs: [CrashlyticsLogEntry]
    var breadcrumbs: [CrashlyticsBreadcrumb]
    var rawJSON: String?

    init(
        eventId: String? = nil,
        resourceName: String? = nil,
        issueId: String? = nil,
        issueTitle: String? = nil,
        issueSubtitle: String? = nil,
        eventTime: String? = nil,
        platform: String? = nil,
        bundleOrPackage: String? = nil,
        processState: String? = nil,
        displayVersion: String? = nil,
        buildVersion: String? = nil,
        deviceModel: String? = nil,
        deviceOrientation: String? = nil,
        osVersion: String? = nil,
        osOrientation: String? = nil,
        jailbroken: Bool? = nil,
        memoryFree: Int? = nil,
        memoryUsed: Int? = nil,
        storageFree: Int? = nil,
        storageUsed: Int? = nil,
        userId: String? = nil,
        blameFrame: CrashlyticsFrame? = nil,
        exceptions: [CrashlyticsException] = [],
        threads: [CrashlyticsThread] = [],
        errors: [CrashlyticsException] = [],
        customKeys: [String: String] = [:],
        logs: [CrashlyticsLogEntry] = [],
        breadcrumbs: [CrashlyticsBreadcrumb] = [],
        rawJSON: String? = nil
    ) {
        self.eventId = eventId
        self.resourceName = resourceName
        self.issueId = issueId
        self.issueTitle = issueTitle
        self.issueSubtitle = issueSubtitle
        self.eventTime = eventTime
        self.platform = platform
        self.bundleOrPackage = bundleOrPackage
        self.processState = processState
        self.displayVersion = displayVersion
        self.buildVersion = buildVersion
        self.deviceModel = deviceModel
        self.deviceOrientation = deviceOrientation
        self.osVersion = osVersion
        self.osOrientation = osOrientation
        self.jailbroken = jailbroken
        self.memoryFree = memoryFree
        self.memoryUsed = memoryUsed
        self.storageFree = storageFree
        self.storageUsed = storageUsed
        self.userId = userId
        self.blameFrame = blameFrame
        self.exceptions = exceptions
        self.threads = threads
        self.errors = errors
        self.customKeys = customKeys
        self.logs = logs
        self.breadcrumbs = breadcrumbs
        self.rawJSON = rawJSON
    }
}
