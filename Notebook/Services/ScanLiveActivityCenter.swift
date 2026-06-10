import Foundation

#if canImport(ActivityKit)
@preconcurrency import ActivityKit

struct ScanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: ScanPhase
        var subject: String
        var pageCount: Int
    }

    var notebookID: UUID
}

@MainActor
final class ScanLiveActivityCenter {
    static let shared = ScanLiveActivityCenter()
    nonisolated(unsafe) private var activity: Activity<ScanActivityAttributes>?

    private init() {}

    func start(notebookID: UUID, subject: String, pageCount: Int) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ScanActivityAttributes(notebookID: notebookID)
        let state = ScanActivityAttributes.ContentState(phase: .capturing, subject: subject, pageCount: pageCount)

        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        } catch {
            activity = nil
        }
    }

    func update(phase: ScanPhase, subject: String, pageCount: Int) async {
        guard let activity else { return }
        let state = ScanActivityAttributes.ContentState(phase: phase, subject: subject, pageCount: pageCount)
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end(phase: ScanPhase = .sorted, subject: String, pageCount: Int) async {
        guard let activity else { return }
        let state = ScanActivityAttributes.ContentState(phase: phase, subject: subject, pageCount: pageCount)
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 3))
        self.activity = nil
    }
}
#else
@MainActor
final class ScanLiveActivityCenter {
    static let shared = ScanLiveActivityCenter()
    private init() {}
    func start(notebookID: UUID, subject: String, pageCount: Int) async {}
    func update(phase: ScanPhase, subject: String, pageCount: Int) async {}
    func end(phase: ScanPhase = .sorted, subject: String, pageCount: Int) async {}
}
#endif
