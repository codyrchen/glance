import Foundation
import os

enum AssistantLog {
    static let subsystem = "dev.codychen.ContextAssistant"
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let llm = Logger(subsystem: subsystem, category: "llm")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let store = Logger(subsystem: subsystem, category: "store")
}
