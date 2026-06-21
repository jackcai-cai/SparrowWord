import Foundation

nonisolated final class StorageService {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let baseFolderName = "SparrowWord"
    private let legacyBaseFolderNames = [
        "WordDock",
        "VoiceNotesMac",
    ]
    private let currentSandboxBundleIdentifier = "com.JackCai.SparrowWord"
    private let legacySandboxBundleIdentifiers = [
        "com.JackCai.VoiceNotesMac",
    ]

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadEntries() -> [VocabEntry] {
        guard let data = try? Data(contentsOf: entriesURL()) else {
            return []
        }

        return (try? decoder.decode([VocabEntry].self, from: data)) ?? []
    }

    func saveEntries(_ entries: [VocabEntry]) throws {
        let data = try encoder.encode(entries)
        try ensureDirectories()
        try data.write(to: entriesURL(), options: .atomic)
    }

    func loadCaptureDrafts() -> [CaptureDraft] {
        guard let data = try? Data(contentsOf: captureDraftsURL()) else {
            return []
        }

        return (try? decoder.decode([CaptureDraft].self, from: data)) ?? []
    }

    func saveCaptureDrafts(_ drafts: [CaptureDraft]) throws {
        let data = try encoder.encode(drafts)
        try ensureDirectories()
        try data.write(to: captureDraftsURL(), options: .atomic)
    }

    func loadLookupHistory() -> [LookupHistoryRecord] {
        guard let data = try? Data(contentsOf: lookupHistoryURL()) else {
            return []
        }

        return (try? decoder.decode([LookupHistoryRecord].self, from: data)) ?? []
    }

    func saveLookupHistory(_ history: [LookupHistoryRecord]) throws {
        let data = try encoder.encode(history)
        try ensureDirectories()
        try data.write(to: lookupHistoryURL(), options: .atomic)
    }

    func loadReviewHistory() -> [ReviewHistoryRecord] {
        guard let data = try? Data(contentsOf: reviewHistoryURL()) else {
            return []
        }

        return (try? decoder.decode([ReviewHistoryRecord].self, from: data)) ?? []
    }

    func saveReviewHistory(_ history: [ReviewHistoryRecord]) throws {
        let data = try encoder.encode(history)
        try ensureDirectories()
        try data.write(to: reviewHistoryURL(), options: .atomic)
    }

    func loadTrashItems() -> [TrashItem] {
        guard let data = try? Data(contentsOf: trashURL()) else {
            return []
        }

        return (try? decoder.decode([TrashItem].self, from: data)) ?? []
    }

    func saveTrashItems(_ items: [TrashItem]) throws {
        let data = try encoder.encode(items)
        try ensureDirectories()
        try data.write(to: trashURL(), options: .atomic)
    }

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL()) else {
            return AppSettings()
        }

        var settings = (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
        settings.offlineResources = rebasedOfflineResourcesManifest(settings.offlineResources)
        return settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try ensureDirectories()
        try data.write(to: settingsURL(), options: .atomic)
    }

    func baseDirectory() -> URL {
        migrateLegacyBaseDirectoryIfNeeded()
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent(baseFolderName, isDirectory: true)
    }

    func offlineResourcesDirectory() -> URL {
        baseDirectory().appendingPathComponent("OfflineResources", isDirectory: true)
    }

    func pythonHelperDirectory() -> URL {
        baseDirectory().appendingPathComponent("LocalPython", isDirectory: true)
    }

    func translationCacheURL() -> URL {
        baseDirectory().appendingPathComponent("translation_cache.json")
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseDirectory(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: offlineResourcesDirectory(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pythonHelperDirectory(), withIntermediateDirectories: true)
    }

    private func entriesURL() -> URL {
        baseDirectory().appendingPathComponent("entries.json")
    }

    private func settingsURL() -> URL {
        baseDirectory().appendingPathComponent("settings.json")
    }

    private func captureDraftsURL() -> URL {
        baseDirectory().appendingPathComponent("capture_drafts.json")
    }

    private func lookupHistoryURL() -> URL {
        baseDirectory().appendingPathComponent("lookup_history.json")
    }

    private func trashURL() -> URL {
        baseDirectory().appendingPathComponent("trash.json")
    }

    private func reviewHistoryURL() -> URL {
        baseDirectory().appendingPathComponent("review_history.json")
    }

    private func migrateLegacyBaseDirectoryIfNeeded() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let newDirectory = support.appendingPathComponent(baseFolderName, isDirectory: true)

        guard !fileManager.fileExists(atPath: newDirectory.path) else {
            return
        }

        var candidates = legacyBaseFolderNames.map { legacyFolderName in
            support.appendingPathComponent(legacyFolderName, isDirectory: true)
        }

        let sandboxBundleIdentifiers = [currentSandboxBundleIdentifier] + legacySandboxBundleIdentifiers
        let sandboxSupportDirectories = sandboxBundleIdentifiers.map { bundleIdentifier in
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Application Support", isDirectory: true)
        }

        for sandboxSupport in sandboxSupportDirectories {
            candidates.append(sandboxSupport.appendingPathComponent(baseFolderName, isDirectory: true))
            candidates.append(contentsOf: legacyBaseFolderNames.map { legacyFolderName in
                sandboxSupport.appendingPathComponent(legacyFolderName, isDirectory: true)
            })
        }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            do {
                try fileManager.copyItem(at: candidate, to: newDirectory)
                return
            } catch {
                continue
            }
        }
    }

    private func rebasedOfflineResourcesManifest(_ manifest: OfflineResourceManifest) -> OfflineResourceManifest {
        let currentResourcesDirectory = offlineResourcesDirectory()
        let currentPythonHelperDirectory = pythonHelperDirectory()

        var updated = manifest

        if manifest.isImported {
            updated.resourcesDirectoryPath = currentResourcesDirectory.path
            updated.ecdictDatabasePath = currentResourcesDirectory
                .appendingPathComponent("ecdict/stardict.db")
                .path
            updated.cedictDatabasePath = currentResourcesDirectory
                .appendingPathComponent("cedict/cedict.sqlite")
                .path
            updated.tatoebaDatabasePath = currentResourcesDirectory
                .appendingPathComponent("tatoeba/tatoeba.sqlite")
                .path
            updated.argosPackagesDirectoryPath = currentResourcesDirectory
                .appendingPathComponent("argos/packages")
                .path
            updated.pythonHelperDirectoryPath = currentPythonHelperDirectory.path
        }

        if updated.sentenceEngineMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.sentenceEngineMessage = defaultSentenceEngineMessage(for: updated)
        } else {
            updated.sentenceEngineMessage = sanitizedSentenceEngineMessage(updated.sentenceEngineMessage)
        }

        return updated
    }

    private func defaultSentenceEngineMessage(for manifest: OfflineResourceManifest) -> String {
        switch manifest.sentenceEngineStatus {
        case .unavailable:
            return manifest.isImported
                ? "句子翻译引擎会在首次查句子时自动准备。"
                : "导入本地词典后，句子翻译才会可用。"
        case .preparing:
            return "正在准备本地句子翻译引擎..."
        case .ready:
            return "本地句子翻译引擎已就绪。"
        case .failed:
            return "本地句子翻译引擎暂时不可用。"
        }
    }

    private func sanitizedSentenceEngineMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if trimmed.contains("cannot be used within an App Sandbox")
            || trimmed.contains("pip-build-env")
            || trimmed.contains("python3.13/site-packages") {
            return "上次准备失败：依赖安装触发了本地编译。请使用 Homebrew Python 3.12（推荐）或 3.11 后重试。"
        }

        if trimmed.count <= 240 {
            return trimmed
        }

        let interestingLines = trimmed
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("File ") && !$0.hasPrefix("Traceback") }

        if let lastMeaningfulLine = interestingLines.last, !lastMeaningfulLine.isEmpty {
            return lastMeaningfulLine
        }

        let index = trimmed.index(trimmed.startIndex, offsetBy: 240)
        return "\(trimmed[..<index])..."
    }
}
