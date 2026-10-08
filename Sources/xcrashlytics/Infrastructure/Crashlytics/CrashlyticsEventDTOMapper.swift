import Foundation

struct CrashlyticsEventDTOMapper: Sendable {
    func event(from dto: CrashlyticsDTO.Event) -> CrashlyticsEvent {
        let resourceName = dto.name?.split(separator: "/").last.map(String.init)
        return CrashlyticsEvent(
            eventId: dto.eventId ?? resourceName,
            resourceName: resourceName,
            issueId: dto.issue?.id,
            issueTitle: dto.issueTitle ?? dto.issue?.title,
            issueSubtitle: dto.issueSubtitle ?? dto.issue?.subtitle,
            eventTime: dto.eventTime,
            platform: dto.platform,
            bundleOrPackage: dto.bundleOrPackage,
            processState: dto.processState,
            displayVersion: dto.version?.displayVersion,
            buildVersion: dto.version?.buildVersion,
            deviceModel: dto.device?.model,
            deviceOrientation: dto.device?.orientation,
            osVersion: dto.operatingSystem?.displayVersion,
            osOrientation: dto.operatingSystem?.orientation,
            jailbroken: dto.operatingSystem?.jailbroken,
            memoryFree: dto.memory?.free?.intValue,
            memoryUsed: dto.memory?.used?.intValue,
            storageFree: dto.storage?.free?.intValue,
            storageUsed: dto.storage?.used?.intValue,
            userId: dto.user?.id,
            blameFrame: dto.blameFrame.map(frame(from:)),
            exceptions: dto.exceptions.map(exception(from:)),
            threads: dto.threads.map(thread(from:)),
            errors: dto.errors.map(exception(from:)),
            customKeys: dto.customKeys?.values ?? [:],
            logs: dto.logs.map { CrashlyticsLogEntry(time: $0.logTime, message: $0.message) },
            breadcrumbs: dto.breadcrumbs.map {
                CrashlyticsBreadcrumb(time: $0.eventTime, title: $0.title, params: $0.params?.values ?? [:])
            },
            rawJSON: dto.rawJSON
        )
    }

    private func thread(from dto: CrashlyticsDTO.Thread) -> CrashlyticsThread {
        CrashlyticsThread(
            name: dto.name, title: dto.title, subtitle: dto.subtitle,
            crashed: dto.crashed == true, blamed: dto.blamed == true,
            signal: dto.signal, signalCode: dto.signalCode, crashAddress: dto.crashAddress?.value,
            queue: dto.queue, frames: dto.frames.map(frame(from:)))
    }

    private func exception(from dto: CrashlyticsDTO.Exception) -> CrashlyticsException {
        CrashlyticsException(
            type: dto.type, exceptionMessage: dto.exceptionMessage, title: dto.title, subtitle: dto.subtitle,
            blamed: dto.blamed == true, frames: dto.frames.map(frame(from:)))
    }

    private func frame(from dto: CrashlyticsDTO.Frame) -> CrashlyticsFrame {
        CrashlyticsFrame(
            symbol: dto.symbol, file: dto.file, line: dto.line?.intValue,
            library: dto.library, owner: dto.owner, blamed: dto.blamed == true,
            offset: dto.offset?.intValue.map(String.init),
            address: dto.address?.value, column: dto.column?.intValue)
    }
}
