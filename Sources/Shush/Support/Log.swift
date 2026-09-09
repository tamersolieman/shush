import OSLog

enum Log {
    static let audio = Logger(subsystem: "ai.pivotstudio.shush", category: "audio")
    static let speech = Logger(subsystem: "ai.pivotstudio.shush", category: "speech")
    static let hotkey = Logger(subsystem: "ai.pivotstudio.shush", category: "hotkey")
    static let inject = Logger(subsystem: "ai.pivotstudio.shush", category: "inject")
    static let app = Logger(subsystem: "ai.pivotstudio.shush", category: "app")
}
