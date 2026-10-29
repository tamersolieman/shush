import Testing
import Foundation
@testable import Shush

@Suite("Sync decisions")
struct SyncDecisionTests {
    private let earlier = Date(timeIntervalSince1970: 1_000_000)
    private let later = Date(timeIntervalSince1970: 1_000_100)

    @Test("no Drive copy: push if there is anything local, otherwise nothing")
    func noRemote() {
        #expect(SyncDecision.decide(remote: nil, lastSeen: nil, dirty: false, hasLocal: true) == .push)
        #expect(SyncDecision.decide(remote: nil, lastSeen: nil, dirty: true, hasLocal: false) == .push)
        #expect(SyncDecision.decide(remote: nil, lastSeen: nil, dirty: false, hasLocal: false) == .none)
    }

    @Test("a first sync with data on both sides merges instead of overwriting either")
    func firstSyncBothSides() {
        #expect(SyncDecision.decide(remote: later, lastSeen: nil, dirty: false, hasLocal: true) == .merge)
        #expect(SyncDecision.decide(remote: later, lastSeen: nil, dirty: false, hasLocal: false) == .pull)
    }

    @Test("pull, push, merge or idle depending on which side changed since they last agreed")
    func sinceLastAgreed() {
        #expect(SyncDecision.decide(remote: later, lastSeen: earlier, dirty: false, hasLocal: true) == .pull)
        #expect(SyncDecision.decide(remote: earlier, lastSeen: earlier, dirty: true, hasLocal: true) == .push)
        #expect(SyncDecision.decide(remote: later, lastSeen: earlier, dirty: true, hasLocal: true) == .merge)
        #expect(SyncDecision.decide(remote: earlier, lastSeen: earlier, dirty: false, hasLocal: true) == .none)
    }

    @Test("sub-second differences are not a change")
    func wholeSeconds() {
        let drifted = earlier.addingTimeInterval(0.7)
        #expect(SyncDecision.isSame(earlier, drifted))
        #expect(SyncDecision.decide(remote: earlier, lastSeen: drifted, dirty: false, hasLocal: true) == .none)
    }
}

@Suite("Transcript merge")
struct RunMergeTests {
    private func run(_ id: UUID = UUID(), daysAgo: Double) -> DictationRun {
        DictationRun(
            id: id,
            date: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(-daysAgo * 86_400),
            engine: "apple", audioSeconds: 1, processSeconds: 1, text: "t"
        )
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("local and remote runs combine oldest first, and a run seen on both sides counts once")
    func combines() {
        let shared = run(daysAgo: 2)
        let merged = RunStore.merge(
            local: [shared, run(daysAgo: 0)],
            remote: [run(daysAgo: 3), shared],
            hidden: [], limit: 0, maxAge: nil, now: now
        )
        #expect(merged.map(\.date) == merged.map(\.date).sorted())
        #expect(merged.count == 3)
    }

    @Test("hidden runs, runs past auto-delete, and runs beyond the history limit are dropped")
    func filters() {
        let hidden = run(daysAgo: 1)
        let merged = RunStore.merge(
            local: [run(daysAgo: 0)],
            remote: [hidden, run(daysAgo: 10), run(daysAgo: 2)],
            hidden: [hidden.id], limit: 1, maxAge: 5 * 86_400, now: now
        )
        #expect(merged.count == 1)
        #expect(merged.first?.date == now)
    }
}

@Suite("Token refresh failures")
struct RefreshFailureTests {
    private func body(_ error: String) -> Data { Data(#"{"error":"\#(error)"}"#.utf8) }

    @Test("only Google reporting a revoked grant counts as signed out")
    func onlyInvalidGrantSignsOut() {
        #expect(GoogleAuthService.isRevokedGrant(status: 400, body: body("invalid_grant")))
        #expect(!GoogleAuthService.isRevokedGrant(status: 400, body: body("invalid_request")))
        #expect(!GoogleAuthService.isRevokedGrant(status: 500, body: body("invalid_grant")))
        #expect(!GoogleAuthService.isRevokedGrant(status: 429, body: Data()))
        #expect(!GoogleAuthService.isRevokedGrant(status: 0, body: Data()))
    }
}
