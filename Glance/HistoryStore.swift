import GlanceCore
import Foundation

@MainActor
final class HistoryStore {
    private let fileURL: URL
    private let maxTurns = 30
    private let maxCharacters = 80_000

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Glance", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("history.json")
    }

    func load() -> [ConversationTurn] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let turns = try decoder.decode([ConversationTurn].self, from: data)
            return HistoryTrimmer.trim(turns, maxTurns: maxTurns, maxCharacters: maxCharacters)
        } catch {
            AssistantLog.store.error("History file could not be read: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ turns: [ConversationTurn]) throws {
        let trimmed = HistoryTrimmer.trim(turns, maxTurns: maxTurns, maxCharacters: maxCharacters)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(trimmed)
        try data.write(to: fileURL, options: .atomic)
    }

    var locationDescription: String { fileURL.path }
}
