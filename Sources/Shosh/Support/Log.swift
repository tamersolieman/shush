import OSLog

enum Log {
    static let audio = Logger(subsystem: "ai.pivotstudio.shosh", category: "audio")
    static let speech = Logger(subsystem: "ai.pivotstudio.shosh", category: "speech")
    static let hotkey = Logger(subsystem: "ai.pivotstudio.shosh", category: "hotkey")
    static let inject = Logger(subsystem: "ai.pivotstudio.shosh", category: "inject")
    static let app = Logger(subsystem: "ai.pivotstudio.shosh", category: "app")
}
