import Foundation

enum SyncAction: Equatable {
    case none, pull, push
    /// Both sides changed since they last agreed.
    case merge
}

/// Decides which way one synced item has to move.
///
/// It asks "has each side changed since they last agreed", not "whose clock is later": two
/// Macs with slightly different clocks can otherwise make one machine's edit look older than
/// something it never saw, and drop it. Clocks only ever break a tie for plain settings.
enum SyncDecision {
    /// - remote: the Drive copy's `updatedAt`, nil when there is no copy yet.
    /// - lastSeen: the Drive copy's `updatedAt` as of this Mac's last successful sync of it.
    /// - dirty: this Mac has changed the item since, including while signed out or offline.
    /// - hasLocal: this Mac has any data for the item at all, from before syncing was on.
    static func decide(remote: Date?, lastSeen: Date?, dirty: Bool, hasLocal: Bool) -> SyncAction {
        guard let remote else { return dirty || hasLocal ? .push : .none }

        let remoteChanged = lastSeen.map { !isSame($0, remote) } ?? true
        let localChanged = dirty || (lastSeen == nil && hasLocal)

        switch (remoteChanged, localChanged) {
        case (true, true): return .merge
        case (true, false): return .pull
        case (false, true): return .push
        case (false, false): return .none
        }
    }

    /// Drive keeps whole seconds, so compare at that precision — a sub-second local timestamp
    /// would otherwise look different from its own upload forever.
    static func isSame(_ a: Date, _ b: Date) -> Bool {
        a.timeIntervalSince1970.rounded(.down) == b.timeIntervalSince1970.rounded(.down)
    }
}
