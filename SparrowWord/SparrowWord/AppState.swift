import AppKit
import Combine
import Dispatch
import Foundation
import ImageIO
import SwiftUI
import Vision

@MainActor
final class AppState: ObservableObject {
    nonisolated private static let offlineLexiconEnrichmentVersion = 1
    nonisolated private static let backgroundLexiconRefreshStatusMessage = "正在后台补全离线词典内容，不影响使用。"

    @Published var entries: [VocabEntry]
    @Published var lookupHistory: [LookupHistoryRecord]
    @Published var reviewHistory: [ReviewHistoryRecord]
    @Published var trashItems: [TrashItem]
    @Published var settings: AppSettings
    @Published var openAIAPIKey: String
    @Published var captureDraft = CaptureDraft()
    @Published var savedCaptureDrafts: [CaptureDraft]
    @Published var lookupDraft = LookupDraft()
    @Published var selectedSection: SidebarSection? = .lookup
    @Published var selectedLibraryID: UUID?
    @Published var selectedLibraryCollectionID = LibraryCollectionOption.system.id
    @Published var selectedLookupHistoryID: UUID?
    @Published var selectedReviewSources = Set(ReviewSourceKind.allCases)
    @Published var reviewSortOption: ReviewSortOption = .priority
    @Published var isSelectingReviewItems = false
    @Published var selectedReviewItemIDs: Set<UUID> = []
    @Published var reviewAnswerDraft = ReviewAnswerDraft()
    @Published var showingSettings = false
    @Published var statusMessage = "Ready to capture your next word."
    @Published private(set) var generatingEntryIDs: Set<UUID> = []
    @Published private(set) var isOpenAIAPIKeyStored = false
    @Published private(set) var isTestingOpenAI = false
    @Published private(set) var openAITestMessage = ""
    @Published private(set) var didLastOpenAITestSucceed = false
    @Published private(set) var isLookingUp = false
    @Published private(set) var activeLookupCorrection: LookupCorrection?
    @Published private(set) var lookupSuggestions: [LookupSuggestion] = []
    @Published private(set) var hasAttemptedSentenceLookupInSession = false
    @Published private(set) var lookupViewState: LookupViewState = .idle
    @Published private(set) var latestLookupRecordID: UUID?
    @Published private(set) var isImportingOfflineResources = false
    @Published private(set) var offlineResourceStatusMessage = ""
    @Published private(set) var reviewSessionQueueIDs: [UUID] = []
    @Published private(set) var reviewSessionTotalCount = 0
    @Published private(set) var reviewCompletedCount = 0
    @Published private(set) var reviewSessionConfiguration = ReviewSessionConfiguration(questionTypes: ReviewQuestionType.allCases)

    private let storage = StorageService()
    private let keychain = KeychainService()
    private let generator = DraftGenerationService()
    private let lookupService = LookupService()
    private let offlineResourceService = OfflineResourcesService()
    private let reviewEngine = ReviewEngine()
    private let screenCaptureOCRService = ScreenCaptureOCRService()
    private var generationTasks: [UUID: Task<Void, Never>] = [:]
    private var currentLookupTask: Task<Void, Never>?
    private var lookupSuggestionTask: Task<Void, Never>?
    private var captureSuggestionTask: Task<Void, Never>?
    private var activeLookupRequestID: UUID?
    private var activeLookupHistoryRecordID: UUID?
    private var activeLookupSourceContext: String?
    private var lastCaptureSuggestionSeedKey: String?
    private var libraryRandomRanks: [UUID: Int] = [:]
    private var currentReviewSessionID: UUID?
    private var currentReviewSessionStartedAt: Date?
    private var startupOfflineLexiconEnrichmentWorkItem: DispatchWorkItem?

    init() {
        let storage = StorageService()
        let keychain = KeychainService()
        let loadedEntries = storage.loadEntries()
            .map { Self.normalizedLoadedEntry($0) }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
        let rawCaptureDrafts = storage.loadCaptureDrafts()
        let loadedCaptureDrafts = rawCaptureDrafts
            .map { Self.normalizedLoadedCaptureDraft($0) }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
        let loadedLookupHistory = storage.loadLookupHistory()
            .map { Self.normalizedLoadedLookupHistoryRecord($0) }
            .sorted(by: { $0.queriedAt > $1.queriedAt })
        let rawReviewHistory = storage.loadReviewHistory()
        let normalizedReviewHistory = Self.normalizedLoadedReviewHistory(rawReviewHistory)
        let loadedReviewHistory = normalizedReviewHistory
            .sorted(by: { $0.reviewedAt > $1.reviewedAt })
        let loadedTrashItems = storage.loadTrashItems()
            .map { Self.normalizedLoadedTrashItem($0) }
            .sorted(by: { $0.deletedAt > $1.deletedAt })
        var loadedSettings = storage.loadSettings()
        if let seededManifest = offlineResourceService.seedBundledECDICTIfNeeded(into: loadedSettings.offlineResources) {
            loadedSettings.offlineResources = seededManifest
            try? storage.saveSettings(loadedSettings)
        }
        let storedAPIKey = keychain.loadOpenAIAPIKey()
        let legacyAPIKey = loadedSettings.trimmedLegacyOpenAIAPIKey

        var resolvedAPIKey = storedAPIKey
        var initialStatusMessage: String?
        var isAPIKeyStored = !storedAPIKey.isEmpty

        if resolvedAPIKey.isEmpty, !legacyAPIKey.isEmpty {
            do {
                try keychain.saveOpenAIAPIKey(legacyAPIKey)
                resolvedAPIKey = legacyAPIKey
                isAPIKeyStored = true
                loadedSettings.clearLegacyOpenAIAPIKey()
                try? storage.saveSettings(loadedSettings)
            } catch {
                resolvedAPIKey = legacyAPIKey
                isAPIKeyStored = false
                initialStatusMessage = "旧版 API key 迁移到 Keychain 失败：\(error.localizedDescription)"
            }
        } else if !legacyAPIKey.isEmpty {
            loadedSettings.clearLegacyOpenAIAPIKey()
            try? storage.saveSettings(loadedSettings)
        }

        let migratedState = Self.migrateLegacyInboxState(
            entries: loadedEntries,
            captureDrafts: loadedCaptureDrafts,
            trashItems: loadedTrashItems
        )

        self.entries = migratedState.entries
        self.lookupHistory = loadedLookupHistory
        self.reviewHistory = loadedReviewHistory
        self.trashItems = migratedState.trashItems
        self.settings = loadedSettings
        self.openAIAPIKey = resolvedAPIKey
        self.isOpenAIAPIKeyStored = isAPIKeyStored
        self.savedCaptureDrafts = migratedState.captureDrafts
        self.selectedLibraryID = entries.first(where: { $0.status == .library })?.id
        self.selectedLookupHistoryID = loadedLookupHistory.first?.id
        self.latestLookupRecordID = loadedLookupHistory.first?.id
        self.lookupViewState = loadedLookupHistory.first.map { .success(recordID: $0.id) } ?? .idle
        reshuffleLibraryRandomOrder()

        if let initialStatusMessage {
            self.statusMessage = initialStatusMessage
        }

        self.offlineResourceStatusMessage = loadedSettings.offlineResources.isImported
            ? "本地离线资源已导入。"
            : "还没有导入本地离线词典。"

        if normalizedReviewHistory != rawReviewHistory {
            try? storage.saveReviewHistory(normalizedReviewHistory)
        }

        if migratedState.didChange {
            try? storage.saveEntries(migratedState.entries)
            try? storage.saveCaptureDrafts(migratedState.captureDrafts)
            try? storage.saveTrashItems(migratedState.trashItems)
        }

        scheduleStartupOfflineLexiconEnrichmentIfNeeded(
            initialEntries: loadedEntries,
            initialLookupHistory: loadedLookupHistory,
            manifest: loadedSettings.offlineResources
        )
    }

    deinit {
        startupOfflineLexiconEnrichmentWorkItem?.cancel()
        generationTasks.values.forEach { $0.cancel() }
        currentLookupTask?.cancel()
        lookupSuggestionTask?.cancel()
    }

    private func scheduleStartupOfflineLexiconEnrichmentIfNeeded(
        initialEntries: [VocabEntry],
        initialLookupHistory: [LookupHistoryRecord],
        manifest: OfflineResourceManifest
    ) {
        guard manifest.isImported else {
            return
        }

        guard manifest.lexiconEnrichmentVersion < Self.offlineLexiconEnrichmentVersion else {
            return
        }

        guard Self.hasPendingOfflineLexiconEnrichment(
            entries: initialEntries,
            lookupHistory: initialLookupHistory
        ) else {
            settings.offlineResources.lexiconEnrichmentVersion = Self.offlineLexiconEnrichmentVersion
            persistSettingsSilently()
            return
        }

        let baselineEntries = initialEntries
        let baselineLookupHistory = initialLookupHistory
        let manifestCopy = manifest
        let originalStatusMessage = statusMessage
        let shouldShowProgressMessage = originalStatusMessage == "Ready to capture your next word."

        if shouldShowProgressMessage {
            statusMessage = Self.backgroundLexiconRefreshStatusMessage
        }

        startupOfflineLexiconEnrichmentWorkItem?.cancel()

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem(qos: .utility) { [weak self] in
            guard workItem?.isCancelled == false else {
                return
            }

            let refreshedData = Self.enrichedLoadedOfflineData(
                entries: baselineEntries,
                lookupHistory: baselineLookupHistory,
                manifest: manifestCopy
            )

            guard workItem?.isCancelled == false else {
                return
            }

            let entriesChanged = refreshedData.entries != baselineEntries
            let lookupHistoryChanged = refreshedData.lookupHistory != baselineLookupHistory

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard workItem?.isCancelled == false else {
                    return
                }

                defer {
                    if shouldShowProgressMessage,
                       self.statusMessage == Self.backgroundLexiconRefreshStatusMessage {
                        self.statusMessage = originalStatusMessage
                    }
                    self.startupOfflineLexiconEnrichmentWorkItem = nil
                }

                guard self.settings.offlineResources.lexiconEnrichmentVersion < Self.offlineLexiconEnrichmentVersion else {
                    return
                }

                let appliedEntries = entriesChanged && self.entries == baselineEntries
                if appliedEntries {
                    self.entries = refreshedData.entries
                    try? self.storage.saveEntries(refreshedData.entries)
                }

                let appliedLookupHistory = lookupHistoryChanged && self.lookupHistory == baselineLookupHistory
                if appliedLookupHistory {
                    self.lookupHistory = refreshedData.lookupHistory
                    try? self.storage.saveLookupHistory(refreshedData.lookupHistory)
                }

                let didFinishMigration = (!entriesChanged || appliedEntries)
                    && (!lookupHistoryChanged || appliedLookupHistory)

                guard didFinishMigration else {
                    return
                }

                self.settings.offlineResources.lexiconEnrichmentVersion = Self.offlineLexiconEnrichmentVersion
                self.persistSettingsSilently()
            }
        }

        startupOfflineLexiconEnrichmentWorkItem = workItem

        if let workItem {
            DispatchQueue.global(qos: .utility).async(execute: workItem)
        }
    }

    var displayLanguage: AppDisplayLanguage {
        settings.interfaceLanguage.resolvedLanguage()
    }

    var latestLookupRecord: LookupHistoryRecord? {
        guard let latestLookupRecordID else {
            return lookupHistory.first
        }

        return lookupHistory.first(where: { $0.id == latestLookupRecordID }) ?? lookupHistory.first
    }

    func lookupRecord(id: UUID) -> LookupHistoryRecord? {
        lookupHistory.first(where: { $0.id == id })
    }

    var selectedLookupHistoryRecord: LookupHistoryRecord? {
        guard let selectedLookupHistoryID else {
            return lookupHistory.first
        }

        return lookupHistory.first(where: { $0.id == selectedLookupHistoryID }) ?? lookupHistory.first
    }

    var libraryEntries: [VocabEntry] {
        entries
            .filter { $0.status == .library }
            .sorted(by: compareLibraryEntries(lhs:rhs:))
    }

    var libraryCollectionOptions: [LibraryCollectionOption] {
        let savedOptions = settings.savedLibraryArrangements.map { arrangement in
            LibraryCollectionOption(
                id: arrangement.id.uuidString,
                name: arrangement.name,
                kind: .saved,
                arrangementID: arrangement.id
            )
        }

        return [.system, .favorites] + savedOptions
    }

    var selectedLibraryCollection: LibraryCollectionOption {
        libraryCollectionOptions.first(where: { $0.id == selectedLibraryCollectionID }) ?? .system
    }

    var reviewCard: ReviewCard? {
        reviewEngine.nextCard(from: entries, settings: settings, sessionConfiguration: reviewSessionConfiguration)
    }

    var isReviewSessionActive: Bool {
        reviewSessionTotalCount > 0
    }

    func startReviewSession(with itemIDs: [UUID], configuration: ReviewSessionConfiguration) {
        guard !itemIDs.isEmpty else {
            return
        }

        currentReviewSessionID = UUID()
        currentReviewSessionStartedAt = .now
        reviewSessionConfiguration = configuration
        reviewSessionQueueIDs = itemIDs
        reviewSessionTotalCount = itemIDs.count
        reviewCompletedCount = 0
        reviewAnswerDraft.reset()
        isSelectingReviewItems = false
    }

    func resetReviewSession(clearSelection: Bool = false) {
        currentReviewSessionID = nil
        currentReviewSessionStartedAt = nil
        reviewSessionQueueIDs = []
        reviewSessionTotalCount = 0
        reviewCompletedCount = 0
        reviewAnswerDraft.reset()

        if clearSelection {
            selectedReviewItemIDs.removeAll()
        }
    }

    func moveToPreviousReviewItem() {
        guard reviewSessionQueueIDs.count > 1 else {
            return
        }

        let previousItemID = reviewSessionQueueIDs.removeLast()
        reviewSessionQueueIDs.insert(previousItemID, at: 0)
        reviewAnswerDraft.reset()
    }

    func moveToNextReviewItem() {
        guard reviewSessionQueueIDs.count > 1 else {
            return
        }

        let currentItemID = reviewSessionQueueIDs.removeFirst()
        reviewSessionQueueIDs.append(currentItemID)
        reviewAnswerDraft.reset()
    }

    func reconcileReviewState(with availableItemIDs: Set<UUID>) {
        selectedReviewItemIDs.formIntersection(availableItemIDs)

        if isSelectingReviewItems, availableItemIDs.isEmpty {
            isSelectingReviewItems = false
        }

        let filteredQueueIDs = reviewSessionQueueIDs.filter { availableItemIDs.contains($0) }
        if filteredQueueIDs != reviewSessionQueueIDs {
            reviewSessionQueueIDs = filteredQueueIDs
            reviewSessionTotalCount = reviewCompletedCount + reviewSessionQueueIDs.count
        }

        if reviewSessionQueueIDs.isEmpty, reviewSessionTotalCount == 0 {
            reviewAnswerDraft.reset()
        }
    }

    func completeReviewDecision(
        _ decision: ReviewDecision,
        backingEntryID: UUID?,
        itemID: UUID,
        term: String,
        meaning: String,
        mode: ReviewMode,
        sourceKinds: [ReviewSourceKind],
        isHistoryOnly: Bool
    ) {
        let reviewedAt = Date.now
        let updatedLevels = backingEntryID.flatMap {
            applyReviewDecisionToEntry(decision, for: $0, reviewedAt: reviewedAt)
        }

        let historyRecord = ReviewHistoryRecord(
            reviewedAt: reviewedAt,
            reviewSessionID: currentReviewSessionID,
            reviewSessionStartedAt: currentReviewSessionStartedAt ?? reviewedAt,
            entryID: backingEntryID,
            term: term,
            meaning: meaning,
            mode: mode,
            decision: decision,
            previousProficiency: updatedLevels?.previous,
            resultingProficiency: updatedLevels?.resulting,
            sourceKinds: Array(sourceKinds.uniqued()),
            isHistoryOnly: isHistoryOnly
        )

        reviewHistory.insert(historyRecord, at: 0)
        persistReviewHistory()

        if updatedLevels == nil {
            statusMessage = "\"\(term)\" 来自历史记录，这次复习不会改动词库熟练度。"
        }

        reviewCompletedCount += 1

        if reviewSessionQueueIDs.first == itemID {
            reviewSessionQueueIDs.removeFirst()
        } else {
            reviewSessionQueueIDs.removeAll { $0 == itemID }
        }

        reviewAnswerDraft.reset()
    }

    func lookupCurrentTerm() {
        let trimmedTerm = lookupDraft.trimmedTerm
        guard !trimmedTerm.isEmpty else {
            statusMessage = "先输入要查的单词、词组或句子。"
            return
        }

        if let previousHistoryRecordID = activeLookupHistoryRecordID {
            let previousStatusMessage = progressiveCancellationStatusMessage(for: previousHistoryRecordID)
            updateLookupHistoryRecord(
                id: previousHistoryRecordID,
                status: .cancelled,
                statusMessage: previousStatusMessage
            )
        }

        currentLookupTask?.cancel()

        let requestID = UUID()
        activeLookupRequestID = requestID
        isLookingUp = true
        let originalDraft = lookupDraft
        let settingsSnapshot = settings
        let apiKeySnapshot = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = resolveEnglishLookupCorrectionIfNeeded(
            term: originalDraft.trimmedTerm,
            kind: originalDraft.kind,
            settings: settingsSnapshot
        )
        activeLookupCorrection = correction
        activeLookupSourceContext = normalizedLookupSourceContext(originalDraft.sourceContext)

        var draftSnapshot = originalDraft
        if let correction {
            draftSnapshot.term = correction.correctedTerm
            lookupDraft.term = correction.correctedTerm
        }

        let showsPreviewShell = draftSnapshot.kind != .sentence
        let initialStatusMessage: String
        if containsChineseCharacters(in: draftSnapshot.trimmedTerm) {
            initialStatusMessage = "正在查找英文候选..."
        } else if correction != nil {
            initialStatusMessage = "原词没有命中，已切到纠正拼写继续查询..."
        } else if showsPreviewShell {
            initialStatusMessage = "正在加载中文释义..."
        } else {
            initialStatusMessage = "正在整理这次查词结果..."
        }

        let initialHistoryRecord = recordLookupHistory(
            originalQuery: originalDraft.trimmedTerm,
            content: LookupContent(
                kind: draftSnapshot.kind,
                term: draftSnapshot.trimmedTerm,
                pronunciation: "",
                partOfSpeech: "",
                meanings: [],
                meaningGroups: [],
                examples: [],
                collocations: [],
                translationDirection: draftSnapshot.kind == .sentence
                    ? (containsChineseCharacters(in: draftSnapshot.trimmedTerm) ? .chineseToEnglish : .englishToChinese)
                    : nil
            ),
            source: LookupContentSource(primary: .fallback),
            studyAction: .historyOnly,
            correction: correction,
            status: .inProgress,
            statusMessage: initialStatusMessage
        )
        activeLookupHistoryRecordID = initialHistoryRecord.id

        lookupViewState = .loading(
            query: draftSnapshot.trimmedTerm,
            previewRecord: showsPreviewShell
                ? loadingShellLookupRecord(
                    originalQuery: originalDraft.trimmedTerm,
                    displayTerm: draftSnapshot.trimmedTerm,
                    kind: draftSnapshot.kind,
                    correction: correction
                )
                : nil,
            statusMessage: initialStatusMessage
        )

        currentLookupTask = Task { [weak self] in
            guard let self else {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            if draftSnapshot.kind == .sentence {
                self.hasAttemptedSentenceLookupInSession = true
                await self.handleSentenceLookup(
                    draftSnapshot,
                    originalQuery: originalDraft.trimmedTerm,
                    requestID: requestID,
                    correction: correction
                )
                return
            }

            if containsChineseCharacters(in: draftSnapshot.trimmedTerm) {
                await self.handleChineseLookup(
                    draftSnapshot,
                    requestID: requestID,
                    correction: correction,
                    settings: settingsSnapshot,
                    apiKey: apiKeySnapshot
                )
                return
            }

            await self.handleProgressiveLocalLookup(
                draftSnapshot,
                originalQuery: originalDraft.trimmedTerm,
                requestID: requestID,
                correction: correction,
                settings: settingsSnapshot,
                apiKey: apiKeySnapshot
            )
        }
    }

    func clearLookupCorrection() {
        activeLookupCorrection = nil
    }

    func updateLookupTerm(_ newValue: String) {
        lookupDraft.term = newValue

        if let correction = activeLookupCorrection,
           newValue.trimmingCharacters(in: .whitespacesAndNewlines) != correction.correctedTerm {
            activeLookupCorrection = nil
        }

        refreshLookupSuggestions()
    }

    func handleLookupKindChange() {
        if lookupDraft.kind == .sentence {
            lookupSuggestions = []
        }
        refreshLookupSuggestions()
    }

    func applyLookupSuggestion(_ suggestion: LookupSuggestion) {
        lookupDraft.kind = suggestion.kind
        lookupDraft.term = suggestion.term
        activeLookupCorrection = nil
        refreshLookupSuggestions()
        lookupCurrentTerm()
    }

    private func resolveEnglishLookupCorrectionIfNeeded(
        term: String,
        kind: EntryKind,
        settings: AppSettings
    ) -> LookupCorrection? {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)

        guard kind == .word else {
            return nil
        }

        guard cleanedTerm.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        guard OfflineLexiconService.shared.hasEnglishLookupHit(
            term: cleanedTerm,
            kind: kind,
            manifest: settings.offlineResources
        ) == false else {
            return nil
        }

        let spellChecker = NSSpellChecker.shared
        let wordRange = NSRange(location: 0, length: (cleanedTerm as NSString).length)
        let misspelledRange = spellChecker.checkSpelling(of: cleanedTerm, startingAt: 0)

        guard misspelledRange.location != NSNotFound else {
            return nil
        }

        let documentTag = NSSpellChecker.uniqueSpellDocumentTag()
        defer {
            spellChecker.closeSpellDocument(withTag: documentTag)
        }

        let suggestions = spellChecker.guesses(
            forWordRange: wordRange,
            in: cleanedTerm,
            language: "en_US",
            inSpellDocumentWithTag: documentTag
        ) ?? []

        for suggestion in suggestions {
            let cleanedSuggestion = suggestion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !cleanedSuggestion.isEmpty else {
                continue
            }

            guard cleanedSuggestion.caseInsensitiveCompare(cleanedTerm) != ComparisonResult.orderedSame else {
                continue
            }

            guard isSingleEditOrTransposition(cleanedTerm.lowercased(), cleanedSuggestion.lowercased()) else {
                continue
            }

            guard OfflineLexiconService.shared.hasEnglishLookupHit(
                term: cleanedSuggestion,
                kind: kind,
                manifest: settings.offlineResources
            ) else {
                continue
            }

            return LookupCorrection(
                originalTerm: cleanedTerm,
                correctedTerm: cleanedSuggestion
            )
        }

        return nil
    }

    private func isSingleEditOrTransposition(_ original: String, _ candidate: String) -> Bool {
        if original == candidate {
            return false
        }

        if original.count == candidate.count {
            let originalChars = Array(original)
            let candidateChars = Array(candidate)
            var differences: [Int] = []

            for index in originalChars.indices where originalChars[index] != candidateChars[index] {
                differences.append(index)
                if differences.count > 2 {
                    break
                }
            }

            if differences.count == 1 {
                return true
            }

            if differences.count == 2 {
                let first = differences[0]
                let second = differences[1]
                return originalChars[first] == candidateChars[second]
                    && originalChars[second] == candidateChars[first]
            }
        }

        if abs(original.count - candidate.count) != 1 {
            return false
        }

        let shorter = Array(original.count < candidate.count ? original : candidate)
        let longer = Array(original.count < candidate.count ? candidate : original)
        var shortIndex = 0
        var longIndex = 0
        var skipped = false

        while shortIndex < shorter.count, longIndex < longer.count {
            if shorter[shortIndex] == longer[longIndex] {
                shortIndex += 1
                longIndex += 1
                continue
            }

            guard skipped == false else {
                return false
            }

            skipped = true
            longIndex += 1
        }

        return true
    }

    func startLookup(term: String, kind: EntryKind) {
        lookupDraft.kind = kind
        lookupDraft.term = term
        lookupDraft.sourceContext = ""
        lookupSuggestions = []
        lookupCurrentTerm()
    }

    func updateLookupSourceContext(_ newValue: String) {
        lookupDraft.sourceContext = newValue

        guard isLookingUp else {
            return
        }

        guard case .loading(let activeQuery, _, _) = lookupViewState,
              lookupDraft.trimmedTerm == activeQuery else {
            return
        }

        activeLookupSourceContext = normalizedLookupSourceContext(lookupDraft.sourceContext)
    }

    func refreshLookupSuggestions() {
        lookupSuggestionTask?.cancel()

        let trimmedTerm = lookupDraft.trimmedTerm
        let kind = lookupDraft.kind
        let manifest = settings.offlineResources

        guard kind != .sentence,
              trimmedTerm.count >= 2,
              containsChineseCharacters(in: trimmedTerm) == false else {
            lookupSuggestions = []
            return
        }

        lookupSuggestionTask = Task { [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else {
                return
            }

            let suggestions = await Task.detached(priority: .userInitiated) {
                OfflineLexiconService.shared.lookupSuggestions(
                    term: trimmedTerm,
                    kind: kind,
                    manifest: manifest
                )
            }.value

            guard !Task.isCancelled else {
                return
            }

            guard self.lookupDraft.trimmedTerm == trimmedTerm, self.lookupDraft.kind == kind else {
                return
            }

            self.lookupSuggestions = suggestions
        }
    }

    func captureTextFromScreen() async throws -> String {
        try await screenCaptureOCRService.captureRecognizedText()
    }

    func moveSortRule(from source: IndexSet, to destination: Int) {
        settings.entrySortRules.move(fromOffsets: source, toOffset: destination)
    }

    func moveSortRule(_ criterion: EntrySortCriterion, to targetCriterion: EntrySortCriterion) {
        guard let sourceIndex = settings.entrySortRules.firstIndex(where: { $0.criterion == criterion }),
              let targetIndex = settings.entrySortRules.firstIndex(where: { $0.criterion == targetCriterion }),
              sourceIndex != targetIndex else {
            return
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        settings.entrySortRules.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
    }

    func moveSortRuleUp(_ criterion: EntrySortCriterion) {
        guard let index = settings.entrySortRules.firstIndex(where: { $0.criterion == criterion }),
              index > 0 else {
            return
        }

        settings.entrySortRules.swapAt(index, index - 1)
    }

    func moveSortRuleDown(_ criterion: EntrySortCriterion) {
        guard let index = settings.entrySortRules.firstIndex(where: { $0.criterion == criterion }),
              index < settings.entrySortRules.count - 1 else {
            return
        }

        settings.entrySortRules.swapAt(index, index + 1)
    }

    func toggleSortRuleDirection(_ criterion: EntrySortCriterion) {
        guard let index = settings.entrySortRules.firstIndex(where: { $0.criterion == criterion }) else {
            return
        }

        settings.entrySortRules[index].direction = settings.entrySortRules[index].direction.next()

        if settings.entrySortRules[index].direction == .random {
            reshuffleLibraryRandomOrder()
        }
    }

    func reshuffleLibraryRandomOrder() {
        let ids = entries
            .filter { $0.status == .library }
            .map(\.id)
            .shuffled()

        libraryRandomRanks = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
    }

    func toggleFavorite(for entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        entries[index].isFavorite.toggle()
        entries[index].updatedAt = .now
        persistEntries()
        statusMessage = entries[index].isFavorite
            ? "\"\(entries[index].term)\" 已加入收藏。"
            : "\"\(entries[index].term)\" 已取消收藏。"
    }

    func entries(for collection: LibraryCollectionOption) -> [VocabEntry] {
        switch collection.kind {
        case .system:
            return libraryEntries
        case .favorites:
            return libraryEntries.filter(\.isFavorite)
        case .saved:
            guard let arrangementID = collection.arrangementID,
                  let arrangement = settings.savedLibraryArrangements.first(where: { $0.id == arrangementID }) else {
                return []
            }

            let lookup = Dictionary(uniqueKeysWithValues: libraryEntries.map { ($0.id, $0) })
            let ordered = arrangement.entryIDs.compactMap { lookup[$0] }
            return ordered
        }
    }

    func saveLibraryArrangement(name: String, entryIDs: [UUID]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "排列 \(settings.savedLibraryArrangements.count + 1)" : trimmedName

        let arrangement = SavedLibraryArrangement(
            id: UUID(),
            name: finalName,
            entryIDs: entryIDs.uniqued()
        )

        settings.savedLibraryArrangements.append(arrangement)
        settings.normalize()
        selectedLibraryCollectionID = arrangement.id.uuidString
        persistSettings()
        statusMessage = "\"\(finalName)\" 已保存。"
    }

    func moveEntry(_ entryID: UUID, inSavedArrangement arrangementID: UUID, to targetEntryID: UUID) {
        guard let arrangementIndex = settings.savedLibraryArrangements.firstIndex(where: { $0.id == arrangementID }) else {
            return
        }

        var entryIDs = settings.savedLibraryArrangements[arrangementIndex].entryIDs
        guard let sourceIndex = entryIDs.firstIndex(of: entryID),
              let targetIndex = entryIDs.firstIndex(of: targetEntryID),
              sourceIndex != targetIndex else {
            return
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        entryIDs.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        settings.savedLibraryArrangements[arrangementIndex].entryIDs = entryIDs
        persistSettings()
    }

    var openAIAPIKeyStorageStatusText: String {
        isOpenAIAPIKeyStored ? "已存储" : "未存储"
    }

    var offlineResourcesStatusText: String {
        if isImportingOfflineResources {
            return "正在导入本地词典..."
        }

        if settings.offlineResources.isImported {
            return "已导入"
        }

        return "未导入"
    }

    var sentenceEngineStatusText: String {
        settings.offlineResources.sentenceEngineStatus.title
    }

    var sentenceEngineStatusColor: Color {
        switch settings.offlineResources.sentenceEngineStatus {
        case .unavailable:
            return .secondary
        case .preparing:
            return .orange
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }

    var sentenceEngineDisplayMessage: String {
        let trimmedMessage = settings.offlineResources.sentenceEngineMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedMessage.isEmpty {
            return trimmedMessage
        }

        return settings.offlineResources.isImported
            ? "句子翻译引擎会在首次查句子时自动准备。"
            : "导入本地词典后，句子翻译才会可用。"
    }

    var sentenceEngineMessageColor: Color {
        settings.offlineResources.sentenceEngineStatus == .failed ? .red : .secondary
    }

    private var showsSentenceEngineRetryHint: Bool {
        settings.offlineResources.sentenceEngineStatus == .failed && !hasAttemptedSentenceLookupInSession
    }

    var sentenceEngineLookupStatusText: String {
        if showsSentenceEngineRetryHint {
            return "待重试"
        }

        return sentenceEngineStatusText
    }

    var sentenceEngineLookupStatusColor: Color {
        if showsSentenceEngineRetryHint {
            return .secondary
        }

        return sentenceEngineStatusColor
    }

    var sentenceEngineLookupMessage: String {
        if showsSentenceEngineRetryHint {
            return "上次准备失败。输入一句话后会重新尝试本地句子引擎。"
        }

        return sentenceEngineDisplayMessage
    }

    var sentenceEngineLookupMessageColor: Color {
        if showsSentenceEngineRetryHint {
            return .secondary
        }

        return sentenceEngineMessageColor
    }

    var defaultOfflineDictionaryFolderPath: String {
        offlineResourceService.defaultSourceDirectory().path
    }

    func isGeneratingEntry(_ entryID: UUID) -> Bool {
        generatingEntryIDs.contains(entryID)
    }

    var currentSavedCaptureDraft: CaptureDraft? {
        guard !captureDraft.trimmedTerm.isEmpty else {
            return nil
        }

        let currentKey = captureDraftStorageKey(for: captureDraft)
        return savedCaptureDrafts.first(where: { captureDraftStorageKey(for: $0) == currentKey })
    }

    var currentCaptureLibraryEntry: VocabEntry? {
        guard !captureDraft.trimmedTerm.isEmpty else {
            return nil
        }

        return matchingLibraryEntry(term: captureDraft.trimmedTerm, kind: captureDraft.kind)
    }

    func startFreshCaptureDraft() {
        captureDraft = CaptureDraft(proficiency: captureDraft.proficiency)
        lastCaptureSuggestionSeedKey = nil
        statusMessage = "Ready to capture your next word."
    }

    func restoreCaptureDraft(_ draftID: UUID) {
        guard let draft = savedCaptureDrafts.first(where: { $0.id == draftID }) else {
            return
        }

        captureDraft = draft
        lastCaptureSuggestionSeedKey = captureSuggestionSeedKey(for: draft.trimmedTerm, kind: draft.kind)
        statusMessage = "已载入保存的 Quick Capture 草稿。"
    }

    func fillCaptureDraftSuggestions() {
        guard captureDraft.isValid else {
            statusMessage = "先输入词、词组或句子，再生成建议。"
            return
        }

        captureDraft = resolvedCaptureDraft(captureDraft, replaceSuggestionFields: true)
        lastCaptureSuggestionSeedKey = captureSuggestionSeedKey(for: captureDraft.trimmedTerm, kind: captureDraft.kind)
        statusMessage = "已填入建议的释义和例句。"
    }

    func openLookupResultInQuickCapture(_ content: LookupContent, sourceContext: String?) {
        captureDraft = seededCaptureDraft(
            term: content.term,
            kind: content.kind,
            sourceContext: sourceContext,
            partOfSpeech: content.partOfSpeech,
            meaningChoices: Self.normalizedChoiceEntries(
                content.meanings,
                maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
            ),
            meaningGroups: content.meaningGroups,
            exampleChoices: generatedExamples(for: content, sourceContext: sourceContext),
            notes: ""
        )
        lastCaptureSuggestionSeedKey = captureSuggestionSeedKey(for: content.term, kind: content.kind)
        statusMessage = "\"\(content.term)\" 已载入 Quick Capture。"
    }

    func openLookupDraftInQuickCapture(term: String, kind: EntryKind, sourceContext: String?) {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return
        }

        captureDraft = seededCaptureDraft(
            term: cleanedTerm,
            kind: kind,
            sourceContext: sourceContext,
            partOfSpeech: kind == .phrase ? "phr." : "",
            meaningChoices: [],
            exampleChoices: [],
            notes: ""
        )
        lastCaptureSuggestionSeedKey = nil
        scheduleAutomaticCaptureSuggestions()
        statusMessage = "\"\(cleanedTerm)\" 已先载入 Quick Capture，建议会自动补齐。"
    }

    func openReverseCandidateInQuickCapture(_ candidate: ReverseLookupCandidate, sourceContext: String?) {
        let kind = resolvedLookupKind(for: candidate.english, preferredKind: .word)
        captureDraft = seededCaptureDraft(
            term: candidate.english,
            kind: kind,
            sourceContext: sourceContext,
            partOfSpeech: kind == .phrase ? "短语" : "",
            meaningChoices: [candidate.chinese],
            exampleChoices: [],
            notes: "中文反查候选：\(candidate.chinese)"
        )
        lastCaptureSuggestionSeedKey = captureSuggestionSeedKey(for: candidate.english, kind: kind)
        statusMessage = "\"\(candidate.english)\" 已载入 Quick Capture。"
    }

    func openLibraryEntryInQuickCapture(_ entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return
        }

        captureDraft = Self.captureDraft(from: entry)
        lastCaptureSuggestionSeedKey = captureSuggestionSeedKey(for: entry.term, kind: entry.kind)
        statusMessage = "\"\(entry.term)\" 已从词库载入 Quick Capture。"
    }

    func scheduleAutomaticCaptureSuggestions() {
        captureSuggestionTask?.cancel()

        let seedKey = captureSuggestionSeedKey(for: captureDraft.trimmedTerm, kind: captureDraft.kind)
        guard seedKey.isEmpty == false else {
            if captureDraft.trimmedTerm.isEmpty {
                lastCaptureSuggestionSeedKey = nil
            }
            return
        }

        guard seedKey != lastCaptureSuggestionSeedKey else {
            return
        }

        captureSuggestionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self else {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            let currentSeedKey = await MainActor.run {
                self.captureSuggestionSeedKey(for: self.captureDraft.trimmedTerm, kind: self.captureDraft.kind)
            }

            guard currentSeedKey == seedKey else {
                return
            }

            await MainActor.run {
                self.captureDraft = self.resolvedCaptureDraft(self.captureDraft, replaceSuggestionFields: true)
                self.lastCaptureSuggestionSeedKey = seedKey
            }
        }
    }

    @discardableResult
    func saveCaptureAsDraft() -> Bool {
        guard captureDraft.isValid else {
            statusMessage = "先输入词、词组或句子。"
            return false
        }

        let draft = resolvedCaptureDraft(captureDraft, replaceSuggestionFields: false)
        captureDraft = draft
        lastCaptureSuggestionSeedKey = captureSuggestionSeedKey(for: draft.trimmedTerm, kind: draft.kind)
        upsertSavedCaptureDraft(draft)
        statusMessage = "\"\(draft.trimmedTerm)\" 已保存为 Quick Capture 草稿。"
        return true
    }

    private func finalizeLibrarySave(_ saveResult: (didSucceed: Bool, entryID: UUID, statusMessage: String)) -> Bool {
        selectedLibraryID = saveResult.entryID
        selectedSection = .library
        persistEntries()
        statusMessage = saveResult.statusMessage
        return true
    }

    @discardableResult
    func saveCaptureToLibrary() -> Bool {
        guard captureDraft.isValid else {
            statusMessage = "先输入词、词组或句子。"
            return false
        }

        let draft = resolvedCaptureDraft(captureDraft, replaceSuggestionFields: false)
        let saveResult = saveCaptureDraftToLibrary(draft)
        guard saveResult.didSucceed else {
            return false
        }

        removeSavedCaptureDraft(for: draft)
        captureDraft = CaptureDraft()
        lastCaptureSuggestionSeedKey = nil
        return finalizeLibrarySave(saveResult)
    }

    @discardableResult
    func saveLookupResultToLibrary(_ content: LookupContent, sourceContext: String?) -> Bool {
        let draft = seededCaptureDraft(
            term: content.term,
            kind: content.kind,
            sourceContext: sourceContext,
            partOfSpeech: content.partOfSpeech,
            meaningChoices: Self.normalizedChoiceEntries(
                content.meanings,
                maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
            ),
            meaningGroups: content.meaningGroups,
            exampleChoices: generatedExamples(for: content, sourceContext: sourceContext),
            notes: ""
        )
        let saveResult = saveCaptureDraftToLibrary(draft)
        guard saveResult.didSucceed else {
            return false
        }

        if let index = entries.firstIndex(where: { $0.id == saveResult.entryID }) {
            entries[index].englishDefinitions = content.englishDefinitions
            entries[index].englishSynonyms = content.englishSynonyms
            entries[index].inflectionLines = content.inflectionLines
            entries[index].referenceTags = content.referenceTags
            entries[index].sanitizeSelections()
        }

        return finalizeLibrarySave(saveResult)
    }

    @discardableResult
    func saveReverseCandidateToLibrary(_ candidate: ReverseLookupCandidate, sourceContext: String?) -> Bool {
        let kind = resolvedLookupKind(for: candidate.english, preferredKind: .word)
        let draft = seededCaptureDraft(
            term: candidate.english,
            kind: kind,
            sourceContext: sourceContext,
            partOfSpeech: kind == .phrase ? "短语" : "",
            meaningChoices: [candidate.chinese],
            exampleChoices: [],
            notes: "中文反查候选：\(candidate.chinese)"
        )
        let saveResult = saveCaptureDraftToLibrary(draft)
        guard saveResult.didSucceed else {
            return false
        }

        return finalizeLibrarySave(saveResult)
    }

    @discardableResult
    private func saveCaptureDraftToLibrary(_ draft: CaptureDraft) -> (
        didSucceed: Bool,
        entryID: UUID,
        statusMessage: String
    ) {
        guard draft.hasSelectedMeaning else {
            statusMessage = "至少保留一个中文释义后，再保存进词库。"
            return (false, UUID(), "")
        }

        let normalizedCurrentTerm = normalizedTerm(draft.trimmedTerm)
        let existingLibraryIndex = entries.firstIndex(where: {
            $0.status == .library
                && $0.kind == draft.kind
                && normalizedTerm($0.term) == normalizedCurrentTerm
        })
        let existingLibraryEntry = existingLibraryIndex.flatMap { entries[$0] }

        let mergedMeaningCandidates = Self.mergedCaptureMeaningCandidates(
            current: draft.meaningCandidates,
            existingGroups: existingLibraryEntry?.meaningGroups ?? [],
            existingSelectedMeanings: existingLibraryEntry?.selectedMeanings ?? [],
            fallbackPartOfSpeech: draft.partOfSpeech
        )
        let mergedMeaningChoices = Self.normalizedChoiceEntries(
            mergedMeaningCandidates.map(\.meaning),
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        let selectedMeanings = mergedMeaningCandidates
            .filter(\.isSelected)
            .map(\.meaning)

        let mergedExampleChoices = Self.normalizedChoiceEntries(
            draft.exampleChoices + (existingLibraryEntry?.generatedExamples ?? []),
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )
        let selectedExamples = Self.normalizedChoiceEntries(
            draft.selectedExamples.isEmpty
                ? (existingLibraryEntry?.selectedGeneratedExample.map { [$0] } ?? [])
                : draft.selectedExamples,
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )

        let updatedEntry = VocabEntry(
            id: existingLibraryEntry?.id ?? UUID(),
            createdAt: existingLibraryEntry?.createdAt ?? .now,
            updatedAt: .now,
            kind: draft.kind,
            term: draft.trimmedTerm,
            sourceContext: draft.trimmedSourceContext.isEmpty
                ? (existingLibraryEntry?.sourceContext ?? "")
                : draft.trimmedSourceContext,
            proficiency: draft.proficiency == .unknown
                ? (existingLibraryEntry?.proficiency ?? .unknown)
                : draft.proficiency,
            status: .library,
            partOfSpeech: draft.partOfSpeech.isEmpty
                ? (existingLibraryEntry?.partOfSpeech ?? "")
                : draft.partOfSpeech,
            meaningChoices: mergedMeaningChoices.isEmpty
                ? (existingLibraryEntry?.meaningChoices ?? [])
                : mergedMeaningChoices,
            meaningGroups: Self.meaningGroups(
                from: mergedMeaningCandidates,
                fallbackPartOfSpeech: draft.partOfSpeech.isEmpty
                    ? (existingLibraryEntry?.partOfSpeech ?? "")
                    : draft.partOfSpeech
            ),
            selectedMeaningIndexes: mergedMeaningChoices.isEmpty
                ? (existingLibraryEntry?.selectedMeaningIndexes ?? [])
                : Self.remappedSelectionIndexes(selectedMeanings, in: mergedMeaningChoices),
            generatedExamples: mergedExampleChoices.isEmpty
                ? (existingLibraryEntry?.generatedExamples ?? [])
                : mergedExampleChoices,
            selectedExampleIndexes: mergedExampleChoices.isEmpty
                ? (existingLibraryEntry?.selectedExampleIndexes ?? [])
                : Self.remappedSelectionIndexes(selectedExamples, in: mergedExampleChoices),
            englishDefinitions: existingLibraryEntry?.englishDefinitions ?? [],
            englishSynonyms: existingLibraryEntry?.englishSynonyms ?? [],
            inflectionLines: existingLibraryEntry?.inflectionLines ?? [],
            referenceTags: existingLibraryEntry?.referenceTags ?? [],
            notes: draft.notes.isEmpty ? (existingLibraryEntry?.notes ?? "") : draft.notes,
            isFavorite: existingLibraryEntry?.isFavorite ?? false,
            reviewCount: existingLibraryEntry?.reviewCount ?? 0,
            lastReviewedAt: existingLibraryEntry?.lastReviewedAt
        )

        if let existingLibraryIndex {
            entries[existingLibraryIndex] = updatedEntry
        } else {
            entries.insert(updatedEntry, at: 0)
        }

        return (
            true,
            updatedEntry.id,
            existingLibraryIndex == nil
                ? "\"\(updatedEntry.term)\" 已保存到词库。"
                : "\"\(updatedEntry.term)\" 已更新词库词条。"
        )
    }

    func deleteCurrentSavedCaptureDraft() {
        guard let currentSavedCaptureDraft else {
            return
        }

        savedCaptureDrafts.removeAll { $0.id == currentSavedCaptureDraft.id }
        persistCaptureDrafts()
        statusMessage = "\"\(currentSavedCaptureDraft.trimmedTerm)\" 的 Quick Capture 草稿已删除。"
    }

    func replaceEntry(_ entry: VocabEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        var updatedEntry = entry
        updatedEntry.updatedAt = .now
        updatedEntry.meaningChoices = Self.normalizedChoiceEntries(
            updatedEntry.meaningChoices,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        updatedEntry.generatedExamples = Self.normalizedChoiceEntries(
            updatedEntry.generatedExamples,
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )

        updatedEntry.sanitizeSelections()

        entries[index] = updatedEntry
        persistEntries()
    }

    func regenerateDraft(for entryID: UUID) {
        guard entries.contains(where: { $0.id == entryID }) else {
            return
        }

        requestDraftGeneration(for: entryID, trigger: .manualRefresh)
    }

    @discardableResult
    func approveEntry(_ entryID: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return false
        }

        guard entries[index].hasSelectedMeaning else {
            statusMessage = "至少选择一个中文释义后，才能进入词库。"
            return false
        }

        guard !entries[index].hasAvailableExamples || entries[index].hasSelectedExample else {
            statusMessage = "如果保留了系统例句，请至少选中一个再进入词库。"
            return false
        }

        entries[index].status = .library
        entries[index].updatedAt = .now
        selectedLibraryID = entries[index].id
        selectedSection = .library
        persistEntries()
        statusMessage = "\"\(entries[index].term)\" 已进入词库。"
        return true
    }

    func deleteEntry(_ entryID: UUID) {
        deleteEntries([entryID])
    }

    func deleteEntries(_ entryIDs: Set<UUID>) {
        let deletedEntries = entries.filter { entryIDs.contains($0.id) }
        guard !deletedEntries.isEmpty else {
            return
        }

        archiveTrashItems(deletedEntries.map { TrashItem(entry: $0) })
        entryIDs.forEach(cancelGeneration(for:))
        entries.removeAll { entryIDs.contains($0.id) }

        if let selectedLibraryID, entryIDs.contains(selectedLibraryID) {
            self.selectedLibraryID = libraryEntries.first?.id
        }

        persistEntries()

        if deletedEntries.count == 1, let deletedTerm = deletedEntries.first?.term {
            statusMessage = "\"\(deletedTerm)\" 已移到回收站。"
        } else {
            statusMessage = "已将 \(deletedEntries.count) 个词条移到回收站。"
        }
    }

    func deleteLookupHistoryRecords(_ recordIDs: Set<UUID>) {
        let deletedRecords = lookupHistory.filter { recordIDs.contains($0.id) }
        guard !deletedRecords.isEmpty else {
            return
        }

        archiveTrashItems(deletedRecords.map { TrashItem(historyRecord: $0) })
        lookupHistory.removeAll { recordIDs.contains($0.id) }

        if lookupHistory.isEmpty {
            selectedLookupHistoryID = nil
            latestLookupRecordID = nil
        } else {
            if let selectedLookupHistoryID, recordIDs.contains(selectedLookupHistoryID) {
                self.selectedLookupHistoryID = lookupHistory.first?.id
            }

            if let latestLookupRecordID, recordIDs.contains(latestLookupRecordID) {
                self.latestLookupRecordID = lookupHistory.first?.id
            }
        }

        if case .success(let recordID) = lookupViewState, recordIDs.contains(recordID) {
            if let fallbackRecordID = latestLookupRecordID ?? lookupHistory.first?.id {
                lookupViewState = .success(recordID: fallbackRecordID)
            } else {
                lookupViewState = .idle
            }
        }

        persistLookupHistory()

        if deletedRecords.count == 1, let deletedTerm = deletedRecords.first?.content.term {
            statusMessage = "\"\(deletedTerm)\" 的历史已移到回收站。"
        } else {
            statusMessage = "已将 \(deletedRecords.count) 条历史移到回收站。"
        }
    }

    func permanentlyDeleteTrashItems(_ itemIDs: Set<UUID>) {
        let deletedItems = trashItems.filter { itemIDs.contains($0.id) }
        guard !deletedItems.isEmpty else {
            return
        }

        trashItems.removeAll { itemIDs.contains($0.id) }
        persistTrashItems()

        if deletedItems.count == 1, let deletedTerm = deletedItems.first?.term, !deletedTerm.isEmpty {
            statusMessage = "\"\(deletedTerm)\" 已从回收站彻底删除。"
        } else {
            statusMessage = "已从回收站彻底删除 \(deletedItems.count) 项。"
        }
    }

    func restoreTrashItems(_ itemIDs: Set<UUID>) {
        let itemsToRestore = trashItems.filter { itemIDs.contains($0.id) }
        guard !itemsToRestore.isEmpty else {
            return
        }

        var restoredDraftCount = 0
        var restoredEntryCount = 0
        var restoredHistoryCount = 0

        for item in itemsToRestore {
            if let entry = item.entry {
                if item.sourceCategory == .captureDraft || entry.status == .inbox {
                    upsertRestoredCaptureDraft(Self.captureDraftFromLegacyInboxEntry(entry))
                    restoredDraftCount += 1
                } else {
                    if let existingIndex = entries.firstIndex(where: { $0.id == entry.id }) {
                        entries[existingIndex] = entry
                    } else {
                        entries.append(entry)
                    }
                    selectedLibraryID = entry.id
                    restoredEntryCount += 1
                }
            }

            if let historyRecord = item.historyRecord {
                lookupHistory.removeAll { $0.id == historyRecord.id }
                lookupHistory.append(historyRecord)
                lookupHistory.sort { $0.queriedAt > $1.queriedAt }
                selectedLookupHistoryID = historyRecord.id
                latestLookupRecordID = historyRecord.id
                lookupViewState = .success(recordID: historyRecord.id)
                restoredHistoryCount += 1
            }
        }

        trashItems.removeAll { itemIDs.contains($0.id) }
        persistTrashItems()

        if restoredEntryCount > 0 {
            reshuffleLibraryRandomOrder()
            persistEntries()
        }

        if restoredDraftCount > 0 {
            persistCaptureDrafts()
        }

        if restoredHistoryCount > 0 {
            persistLookupHistory()
        }

        let restoredCount = restoredDraftCount + restoredEntryCount + restoredHistoryCount
        if restoredCount == 1, let restoredTerm = itemsToRestore.first?.term, !restoredTerm.isEmpty {
            statusMessage = "\"\(restoredTerm)\" 已从回收站恢复。"
        } else {
            statusMessage = "已从回收站恢复 \(restoredCount) 项。"
        }
    }

    func emptyTrash() {
        guard !trashItems.isEmpty else {
            statusMessage = "回收站已经是空的。"
            return
        }

        let deletedCount = trashItems.count
        trashItems.removeAll()
        persistTrashItems()
        statusMessage = "回收站已清空，共彻底删除 \(deletedCount) 项。"
    }

    func duplicateEntries(for entryID: UUID) -> [VocabEntry] {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return []
        }

        let normalized = normalizedTerm(entry.term)
        return entries.filter { $0.id != entryID && normalizedTerm($0.term) == normalized }
    }

    func mergeDuplicates(into entryID: UUID) {
        guard let primaryIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        let duplicates = duplicateEntries(for: entryID)
        guard !duplicates.isEmpty else {
            statusMessage = "没有可合并的重复词条。"
            return
        }

        var primary = entries[primaryIndex]

        for duplicate in duplicates {
            if !duplicate.sourceContext.isEmpty, !primary.sourceContext.contains(duplicate.sourceContext) {
                primary.sourceContext = [primary.sourceContext, duplicate.sourceContext]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }

            primary.meaningChoices = Self.normalizedChoiceEntries(
                primary.meaningChoices + duplicate.meaningChoices,
                maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
            )
            primary.meaningGroups = MeaningGroup.normalized(
                primary.meaningGroups + duplicate.meaningGroups,
                fallbackPartOfSpeech: primary.partOfSpeech,
                fallbackMeanings: primary.meaningChoices,
                maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
            )
            primary.generatedExamples = Self.normalizedChoiceEntries(
                primary.generatedExamples + duplicate.generatedExamples,
                maxCount: EntryCandidateDefaults.exampleChoiceCount
            )
            primary.englishDefinitions = Array((primary.englishDefinitions + duplicate.englishDefinitions).uniqued())
            primary.englishSynonyms = Array((primary.englishSynonyms + duplicate.englishSynonyms).uniqued())
            primary.inflectionLines = Array((primary.inflectionLines + duplicate.inflectionLines).uniqued())
            primary.referenceTags = Array((primary.referenceTags + duplicate.referenceTags).uniqued())
            primary.notes = [primary.notes, duplicate.notes]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
            primary.proficiency = max(primary.proficiency, duplicate.proficiency)
            primary.reviewCount += duplicate.reviewCount
            primary.lastReviewedAt = max(primary.lastReviewedAt ?? .distantPast, duplicate.lastReviewedAt ?? .distantPast)
        }

        primary.sanitizeSelections()

        entries[primaryIndex] = primary
        let duplicateIDs = Set(duplicates.map(\.id))
        duplicateIDs.forEach(cancelGeneration(for:))
        entries.removeAll { duplicateIDs.contains($0.id) }

        if !entries.indices.contains(primaryIndex) {
            selectedLibraryID = libraryEntries.first?.id
        } else {
            selectedLibraryID = primary.id
        }

        persistEntries()
        statusMessage = "\"\(primary.term)\" 的重复词条已合并。"
    }

    func applyReviewDecision(_ decision: ReviewDecision, for entryID: UUID) {
        guard let updatedLevels = applyReviewDecisionToEntry(decision, for: entryID, reviewedAt: .now) else {
            return
        }

        statusMessage = "\"\(updatedLevels.term)\" 已更新为 \(updatedLevels.resulting.title)。"
    }

    private func persist(_ failurePrefix: String, _ save: () throws -> Void) {
        do {
            try save()
        } catch {
            statusMessage = "\(failurePrefix)：\(error.localizedDescription)"
        }
    }

    func persistLookupHistory() {
        persist("查词历史保存失败") { try storage.saveLookupHistory(lookupHistory) }
    }

    func persistReviewHistory() {
        persist("复习历史保存失败") { try storage.saveReviewHistory(reviewHistory) }
    }

    func persistSettings() {
        var normalizedSettings = settings
        normalizedSettings.normalize()
        normalizedSettings.clearLegacyOpenAIAPIKey()
        let trimmedAPIKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try keychain.saveOpenAIAPIKey(trimmedAPIKey)
            isOpenAIAPIKeyStored = !trimmedAPIKey.isEmpty
            settings = normalizedSettings
            openAIAPIKey = trimmedAPIKey
            try storage.saveSettings(settings)
            statusMessage = "设置已保存。"
        } catch {
            statusMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    func clearOpenAIAPIKey() {
        do {
            try keychain.deleteOpenAIAPIKey()
            openAIAPIKey = ""
            isOpenAIAPIKeyStored = false
            didLastOpenAITestSucceed = false
            openAITestMessage = "API key 已从 Keychain 清除。"
            statusMessage = "OpenAI API key 已清除。"
        } catch {
            didLastOpenAITestSucceed = false
            openAITestMessage = "清除 API key 失败：\(error.localizedDescription)"
            statusMessage = "清除 API key 失败：\(error.localizedDescription)"
        }
    }

    func testOpenAIConfiguration(settingsOverride: AppSettings? = nil, apiKeyOverride: String? = nil) {
        guard !isTestingOpenAI else {
            return
        }

        isTestingOpenAI = true
        didLastOpenAITestSucceed = false
        openAITestMessage = ""

        let settingsSnapshot = settingsOverride ?? settings
        let apiKeySnapshot = (apiKeyOverride ?? openAIAPIKey).trimmingCharacters(in: .whitespacesAndNewlines)

        Task { [weak self] in
            guard let self else {
                return
            }

            let result = await self.generator.generateDraft(
                term: "issue",
                sourceContext: "We need to address this issue before launch.",
                kind: .word,
                settings: settingsSnapshot,
                apiKey: apiKeySnapshot
            )

            guard !Task.isCancelled else {
                return
            }

            finishOpenAITest(with: result)
        }
    }

    var storagePathDescription: String {
        storage.baseDirectory().path
    }

    private func compareLibraryEntries(lhs: VocabEntry, rhs: VocabEntry) -> Bool {
        for rule in settings.entrySortRules {
            let comparison = compare(lhs: lhs, rhs: rhs, using: rule)
            if comparison != 0 {
                return comparison < 0
            }
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func compare(lhs: VocabEntry, rhs: VocabEntry, using rule: EntrySortRule) -> Int {
        if rule.direction == .random {
            let leftRank = libraryRandomRanks[lhs.id] ?? Int.max
            let rightRank = libraryRandomRanks[rhs.id] ?? Int.max
            if leftRank == rightRank {
                return 0
            }
            return leftRank < rightRank ? -1 : 1
        }

        let baseComparison: Int

        switch rule.criterion {
        case .proficiency:
            baseComparison = lhs.proficiency.rawValue - rhs.proficiency.rawValue
        case .createdAt:
            if lhs.createdAt == rhs.createdAt {
                baseComparison = 0
            } else {
                baseComparison = lhs.createdAt < rhs.createdAt ? -1 : 1
            }
        case .kind:
            let leftIndex = EntryKind.allCases.firstIndex(of: lhs.kind) ?? 0
            let rightIndex = EntryKind.allCases.firstIndex(of: rhs.kind) ?? 0
            baseComparison = leftIndex - rightIndex
        }

        switch rule.direction {
        case .ascending:
            return baseComparison
        case .descending:
            return -baseComparison
        case .random:
            return 0
        }
    }

    private func persistEntries() {
        persist("保存失败") {
            try storage.saveEntries(entries)
            cleanSavedArrangements()
        }
    }

    private func persistCaptureDrafts() {
        persist("保存 Quick Capture 草稿失败") { try storage.saveCaptureDrafts(savedCaptureDrafts) }
    }

    private func persistTrashItems() {
        persist("回收站保存失败") { try storage.saveTrashItems(trashItems) }
    }

    private func archiveTrashItems(_ items: [TrashItem]) {
        guard !items.isEmpty else {
            return
        }

        trashItems.insert(contentsOf: items, at: 0)
        trashItems.sort { $0.deletedAt > $1.deletedAt }
        persistTrashItems()
    }

    private func applyReviewDecisionToEntry(
        _ decision: ReviewDecision,
        for entryID: UUID,
        reviewedAt: Date
    ) -> (term: String, previous: ProficiencyLevel, resulting: ProficiencyLevel)? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return nil
        }

        let previousLevel = entries[index].proficiency

        switch decision {
        case .downgrade:
            entries[index].proficiency = entries[index].proficiency.downgraded()
        case .keep:
            break
        case .upgrade:
            entries[index].proficiency = entries[index].proficiency.upgraded()
        }

        entries[index].reviewCount += 1
        entries[index].lastReviewedAt = reviewedAt
        entries[index].updatedAt = reviewedAt
        persistEntries()

        return (
            term: entries[index].term,
            previous: previousLevel,
            resulting: entries[index].proficiency
        )
    }

    private func finishLookup(
        _ result: LookupGenerationResult,
        requestID: UUID,
        originalQuery: String,
        effectiveDraft: LookupDraft,
        correction: LookupCorrection?
    ) {
        guard isCurrentLookupRequest(requestID) else {
            return
        }

        completeLookup(
            requestID: requestID,
            originalQuery: originalQuery,
            content: result.content,
            source: lookupContentSource(from: result),
            modelName: result.modelName,
            sourceContext: resolvedLookupSourceContext(for: effectiveDraft),
            correction: correction
        ) { studyAction in
            switch studyAction {
            case .createdDraft:
                return "\"\(originalQuery)\" 已查到，并已先存成学习草稿。"
            case .updatedDraft:
                return "\"\(originalQuery)\" 已重新查词，并更新了现有学习草稿。"
            case .alreadyInLibrary:
                return "\"\(originalQuery)\" 已查到；这个词已经在词库里，可继续从词库或 Quick Capture 整理。"
            case .historyOnly:
                return "\"\(originalQuery)\" 已查到，并记录到历史。接下来可以显式保存到 Quick Capture 或词库。"
            case .awaitingCandidateSelection:
                return "请先从中文反查结果里选择一个英文候选。"
            }
        }
    }

    private func completeLookup(
        requestID: UUID,
        originalQuery: String,
        content: LookupContent,
        source: LookupContentSource,
        modelName: String? = nil,
        sourceContext: String?,
        correction: LookupCorrection?,
        statusMessageForStudyAction: (LookupStudyAction) -> String
    ) {
        guard isCurrentLookupRequest(requestID) else {
            return
        }

        let studyAction = lookupHistoryAction(for: content)
        let historyRecord = recordLookupHistory(
            originalQuery: originalQuery,
            content: content,
            source: source,
            modelName: modelName,
            studyAction: studyAction,
            correction: correction,
            existingRecordID: activeLookupHistoryRecordID,
            status: .completed,
            statusMessage: nil
        )
        lookupViewState = .success(recordID: historyRecord.id)
        statusMessage = statusMessageForStudyAction(studyAction)
        isLookingUp = false
        currentLookupTask = nil
        activeLookupRequestID = nil
        activeLookupHistoryRecordID = nil
        activeLookupSourceContext = nil
    }

    private func lookupHistoryAction(for content: LookupContent) -> LookupStudyAction {
        let normalizedLookupTerm = normalizedTerm(content.term)
        let alreadyInLibrary = entries.contains(where: {
            $0.status == .library
                && $0.kind == content.kind
                && normalizedTerm($0.term) == normalizedLookupTerm
        })

        return alreadyInLibrary ? .alreadyInLibrary : .historyOnly
    }

    private func lookupContentSource(from result: LookupGenerationResult) -> LookupContentSource {
        switch result.source {
        case .openAI:
            return LookupContentSource(primary: .openAI)
        case .localFallback:
            return result.localSource ?? LookupContentSource(primary: .fallback)
        }
    }

    @discardableResult
    private func recordLookupHistory(
        originalQuery: String,
        content: LookupContent,
        source: LookupContentSource,
        modelName: String? = nil,
        studyAction: LookupStudyAction,
        reverseLookupCandidates: [ReverseLookupCandidate] = [],
        correction: LookupCorrection? = nil,
        existingRecordID: UUID? = nil,
        status: LookupHistoryStatus = .completed,
        statusMessage: String? = nil
    ) -> LookupHistoryRecord {
        let historyRecord = LookupHistoryRecord(
            id: existingRecordID ?? UUID(),
            queriedAt: .now,
            originalQuery: originalQuery,
            content: content,
            source: source,
            modelName: modelName,
            studyAction: studyAction,
            reverseLookupCandidates: reverseLookupCandidates,
            correction: correction,
            status: status,
            statusMessage: statusMessage
        )

        if let existingRecordID,
           let existingIndex = lookupHistory.firstIndex(where: { $0.id == existingRecordID }) {
            lookupHistory.remove(at: existingIndex)
        }

        lookupHistory.insert(historyRecord, at: 0)
        latestLookupRecordID = historyRecord.id
        selectedLookupHistoryID = historyRecord.id
        persistLookupHistory()
        return historyRecord
    }

    private func updateLookupHistoryRecord(
        id: UUID,
        content: LookupContent? = nil,
        source: LookupContentSource? = nil,
        modelName: String? = nil,
        studyAction: LookupStudyAction? = nil,
        reverseLookupCandidates: [ReverseLookupCandidate]? = nil,
        correction: LookupCorrection? = nil,
        status: LookupHistoryStatus? = nil,
        statusMessage: String? = nil
    ) {
        guard let index = lookupHistory.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let content {
            lookupHistory[index].content = content
        }
        if let source {
            lookupHistory[index].source = source
        }
        if let modelName {
            lookupHistory[index].modelName = modelName
        }
        if let studyAction {
            lookupHistory[index].studyAction = studyAction
        }
        if let reverseLookupCandidates {
            lookupHistory[index].reverseLookupCandidates = reverseLookupCandidates
        }
        if let correction {
            lookupHistory[index].correction = correction
        }
        if let status {
            lookupHistory[index].status = status
        }

        lookupHistory[index].statusMessage = statusMessage
        lookupHistory[index].queriedAt = .now

        let updatedRecord = lookupHistory.remove(at: index)
        lookupHistory.insert(updatedRecord, at: 0)
        latestLookupRecordID = updatedRecord.id
        selectedLookupHistoryID = updatedRecord.id
        persistLookupHistory()
    }

    private func generatedExamples(for content: LookupContent, sourceContext: String?) -> [String] {
        let examples = Self.cleanedGeneratedExamples(
            content.examples.map(\.english),
            term: content.term,
            sourceContext: sourceContext ?? ""
        )
        if !examples.isEmpty {
            return examples
        }

        return Self.fallbackGeneratedExamples(
            term: content.term,
            sourceContext: sourceContext ?? ""
        )
    }

    private func isCurrentLookupRequest(_ requestID: UUID) -> Bool {
        activeLookupRequestID == requestID
    }

    private func handleProgressiveLocalLookup(
        _ draft: LookupDraft,
        originalQuery: String,
        requestID: UUID,
        correction: LookupCorrection?,
        settings: AppSettings,
        apiKey: String
    ) async {
        let query = draft.trimmedTerm
        let kind = draft.kind
        let manifest = settings.offlineResources
        let shellRecord = loadingShellLookupRecord(
            originalQuery: originalQuery,
            displayTerm: query,
            kind: kind,
            correction: correction
        )

        let quickPreviewTask = Task.detached(priority: .userInitiated) {
            OfflineLexiconService.shared.lookupEnglishQuickPreview(
                term: query,
                kind: kind,
                manifest: manifest
            )
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            guard let core = await quickPreviewTask.value else {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            self.updateProgressiveLookupSnapshot(
                requestID: requestID,
                query: query,
                fallbackRecord: shellRecord,
                statusMessage: "释义已就绪，正在补充搭配和例句..."
            ) { record in
                record.content.pronunciation = core.pronunciation
                record.content.partOfSpeech = core.partOfSpeech
                record.content.meanings = core.meanings
                record.content.meaningGroups = core.meaningGroups
                record.content.englishDefinitions = core.englishDefinitions
                record.content.englishSynonyms = core.englishSynonyms
                record.content.inflectionLines = core.inflectionLines
                record.content.referenceTags = core.referenceTags
                record.source = LookupContentSource(
                    primary: core.sourceComponents.first ?? .fallback,
                    components: Array(core.sourceComponents.dropFirst())
                )
            }
        }

        let coreTask = Task.detached(priority: .userInitiated) {
            OfflineLexiconService.shared.lookupEnglishCore(
                term: query,
                kind: kind,
                manifest: manifest
            )
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            guard let core = await coreTask.value else {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            self.updateProgressiveLookupSnapshot(
                requestID: requestID,
                query: query,
                fallbackRecord: shellRecord,
                statusMessage: "搭配已就绪，正在补充例句..."
            ) { record in
                if !core.pronunciation.isEmpty {
                    record.content.pronunciation = core.pronunciation
                }
                if !core.partOfSpeech.isEmpty {
                    record.content.partOfSpeech = core.partOfSpeech
                }
                if !core.meanings.isEmpty {
                    record.content.meanings = core.meanings
                    record.content.meaningGroups = core.meaningGroups
                }
                if !core.collocations.isEmpty {
                    record.content.collocations = core.collocations
                }
                if !core.englishDefinitions.isEmpty {
                    record.content.englishDefinitions = core.englishDefinitions
                }
                if !core.englishSynonyms.isEmpty {
                    record.content.englishSynonyms = core.englishSynonyms
                }
                if !core.inflectionLines.isEmpty {
                    record.content.inflectionLines = core.inflectionLines
                }
                if !core.referenceTags.isEmpty {
                    record.content.referenceTags = core.referenceTags
                }
                record.source = LookupContentSource(
                    primary: core.sourceComponents.first ?? record.source.primary,
                    components: Array((record.source.components + core.sourceComponents.dropFirst()).uniqued())
                )
            }
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            guard let core = await coreTask.value, !core.collocations.isEmpty else {
                return
            }

            var localizedCollocations = core.collocations

            for index in localizedCollocations.indices {
                let rawCollocation = localizedCollocations[index]
                let localizedCollocation = await Task.detached(priority: .utility) {
                    OfflineLexiconService.shared.localizedCollocation(
                        rawCollocation,
                        manifest: manifest
                    )
                }.value

                guard !Task.isCancelled else {
                    return
                }

                guard localizedCollocation != rawCollocation else {
                    continue
                }

                localizedCollocations[index] = localizedCollocation

                self.updateLoadingLookupPreview(
                    requestID: requestID,
                    query: query,
                    fallbackRecord: shellRecord,
                    statusMessage: "正在补充搭配中文..."
                ) { record in
                    record.content.collocations = localizedCollocations
                }
            }
        }

        let examplesTask = Task.detached(priority: .userInitiated) {
            OfflineLexiconService.shared.lookupEnglishExamples(
                term: query,
                manifest: manifest
            )
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            let examples = await examplesTask.value

            guard !Task.isCancelled, !examples.isEmpty else {
                return
            }

            self.updateProgressiveLookupSnapshot(
                requestID: requestID,
                query: query,
                fallbackRecord: shellRecord,
                statusMessage: "例句已就绪，正在整理最终结果..."
            ) { record in
                record.content.examples = Array(examples.prefix(EntryCandidateDefaults.exampleChoiceCount))
                let mergedComponents = Array(
                    ([record.source.primary] + record.source.components + [.tatoeba]).uniqued()
                )
                record.source = LookupContentSource(
                    primary: mergedComponents.first ?? .tatoeba,
                    components: Array(mergedComponents.dropFirst())
                )
            }
        }

        _ = await quickPreviewTask.value
        _ = await coreTask.value
        _ = await examplesTask.value

        let result = await Task.detached(priority: .userInitiated) {
            await LookupService().generateLookup(
                term: query,
                kind: kind,
                settings: settings,
                apiKey: apiKey
            )
        }.value

        guard !Task.isCancelled else {
            return
        }

        finishLookup(
            result,
            requestID: requestID,
            originalQuery: originalQuery,
            effectiveDraft: draft,
            correction: correction
        )
    }

    private func loadingShellLookupRecord(
        originalQuery: String,
        displayTerm: String,
        kind: EntryKind,
        correction: LookupCorrection? = nil
    ) -> LookupHistoryRecord {
        LookupHistoryRecord(
            originalQuery: originalQuery,
            content: LookupContent(
                kind: kind,
                term: displayTerm,
                pronunciation: "",
                partOfSpeech: "",
                meanings: [],
                meaningGroups: [],
                examples: [],
                collocations: [],
                translationDirection: nil
            ),
            source: LookupContentSource(primary: .fallback),
            studyAction: .historyOnly,
            correction: correction
        )
    }

    private func updateLoadingLookupPreview(
        requestID: UUID,
        query: String,
        fallbackRecord: LookupHistoryRecord,
        statusMessage: String,
        mutate: (inout LookupHistoryRecord) -> Void
    ) {
        guard isCurrentLookupRequest(requestID) else {
            return
        }

        guard case .loading(let activeQuery, let previewRecord, _) = lookupViewState,
              activeQuery == query else {
            return
        }

        var updatedRecord = previewRecord ?? fallbackRecord
        mutate(&updatedRecord)

        lookupViewState = .loading(
            query: query,
            previewRecord: updatedRecord,
            statusMessage: statusMessage
        )
    }

    private func updateProgressiveLookupSnapshot(
        requestID: UUID,
        query: String,
        fallbackRecord: LookupHistoryRecord,
        statusMessage: String,
        mutate: (inout LookupHistoryRecord) -> Void
    ) {
        guard isCurrentLookupRequest(requestID) else {
            return
        }

        guard case .loading(let activeQuery, let previewRecord, _) = lookupViewState,
              activeQuery == query else {
            return
        }

        var updatedRecord = previewRecord ?? fallbackRecord
        mutate(&updatedRecord)

        lookupViewState = .loading(
            query: query,
            previewRecord: updatedRecord,
            statusMessage: statusMessage
        )
        self.statusMessage = statusMessage

        guard let activeLookupHistoryRecordID else {
            return
        }

        updateLookupHistoryRecord(
            id: activeLookupHistoryRecordID,
            content: updatedRecord.content,
            source: updatedRecord.source,
            status: .inProgress,
            statusMessage: statusMessage
        )
    }

    private func progressiveCancellationStatusMessage(for historyRecordID: UUID) -> String {
        guard let record = lookupRecord(id: historyRecordID) else {
            return "你在结果完成前切换了新的查询。"
        }

        switch record.studyAction {
        case .createdDraft:
            return "你在例句补完前切换了新的查询；当前释义已先存成学习草稿。"
        case .updatedDraft:
            return "你在例句补完前切换了新的查询；当前释义已先更新学习草稿。"
        case .alreadyInLibrary:
            return "你在例句补完前切换了新的查询；这个词已经在词库里，可继续从词库或 Quick Capture 整理。"
        case .historyOnly, .awaitingCandidateSelection:
            return "你在结果完成前切换了新的查询；当前结果只记录到了历史。"
        }
    }

    private func handleChineseLookup(
        _ draft: LookupDraft,
        requestID: UUID,
        correction: LookupCorrection?,
        settings: AppSettings,
        apiKey: String
    ) async {
        let exactOptions = OfflineLexiconService.shared
            .exactReverseLookupChinese(
                draft.trimmedTerm,
                manifest: settings.offlineResources
            )
            .map { ChineseLookupOption(candidate: $0, sourcePrimary: .cedict) }

        if exactOptions.count > 1 {
            presentChineseLookupCandidates(
                exactOptions,
                query: draft.trimmedTerm,
                preferredKind: draft.kind,
                requestID: requestID,
                correction: correction
            )
            return
        }

        if let exactOption = exactOptions.first {
            await continueResolvedChineseCandidateLookup(
                draft,
                candidate: exactOption.candidate,
                requestID: requestID,
                correction: correction,
                settings: settings,
                sourcePrimary: exactOption.sourcePrimary,
                resolvedKind: exactOption.resolvedKind,
                modelName: exactOption.modelName
            )
            return
        }

        let localOptions: [ChineseLookupOption]
        localOptions = OfflineLexiconService.shared
            .reverseLookupChinese(
                draft.trimmedTerm,
                manifest: settings.offlineResources
            )
            .map { ChineseLookupOption(candidate: $0, sourcePrimary: .cedict) }

        if localOptions.count > 1 {
            presentChineseLookupCandidates(
                localOptions,
                query: draft.trimmedTerm,
                preferredKind: draft.kind,
                requestID: requestID,
                correction: correction
            )
            return
        }

        if let localOption = localOptions.first {
            await continueResolvedChineseCandidateLookup(
                draft,
                candidate: localOption.candidate,
                requestID: requestID,
                correction: correction,
                settings: settings,
                sourcePrimary: localOption.sourcePrimary,
                resolvedKind: localOption.resolvedKind,
                modelName: localOption.modelName
            )
            return
        }

        // Offline ECDICT reverse lookup (Chinese gloss → English) before falling
        // back to the slow engines. This is the path that keeps Chinese reverse
        // lookup instant and offline for words CC-CEDICT doesn't cover.
        let ecdictReverseOptions = OfflineLexiconService.shared
            .reverseLookupChineseInECDICT(
                draft.trimmedTerm,
                manifest: settings.offlineResources
            )
            .map { ChineseLookupOption(candidate: $0, sourcePrimary: .ecdict) }

        if ecdictReverseOptions.count > 1 {
            presentChineseLookupCandidates(
                ecdictReverseOptions,
                query: draft.trimmedTerm,
                preferredKind: draft.kind,
                requestID: requestID,
                correction: correction
            )
            return
        }

        if let ecdictOption = ecdictReverseOptions.first {
            await continueResolvedChineseCandidateLookup(
                draft,
                candidate: ecdictOption.candidate,
                requestID: requestID,
                correction: correction,
                settings: settings,
                sourcePrimary: ecdictOption.sourcePrimary,
                resolvedKind: ecdictOption.resolvedKind,
                modelName: ecdictOption.modelName
            )
            return
        }

        async let translationOptionsTask = translationLookupOptions(
            chinese: draft.trimmedTerm,
            preferredKind: draft.kind,
            settings: settings
        )
        async let aiOptionsTask = aiChineseLookupOptions(
            chinese: draft.trimmedTerm,
            preferredKind: draft.kind,
            settings: settings,
            apiKey: apiKey
        )

        let translationOptions = await translationOptionsTask
        let aiOptions = await aiOptionsTask
        let combinedOptions = combinedChineseLookupOptions(
            localOptions,
            translationOptions,
            aiOptions
        )

        if combinedOptions.count > 1 {
            presentChineseLookupCandidates(
                combinedOptions,
                query: draft.trimmedTerm,
                preferredKind: draft.kind,
                requestID: requestID,
                correction: correction
            )
            return
        }

        if let resolvedOption = combinedOptions.first {
            await continueResolvedChineseCandidateLookup(
                draft,
                candidate: resolvedOption.candidate,
                requestID: requestID,
                correction: correction,
                settings: settings,
                sourcePrimary: resolvedOption.sourcePrimary,
                resolvedKind: resolvedOption.resolvedKind,
                modelName: resolvedOption.modelName
            )
            return
        }

        await handleChineseTranslationFallback(
            draft,
            requestID: requestID,
            correction: correction,
            settings: settings
        )
    }

    private func presentChineseLookupCandidates(
        _ options: [ChineseLookupOption],
        query: String,
        preferredKind: EntryKind,
        requestID: UUID,
        correction: LookupCorrection?
    ) {
        guard isCurrentLookupRequest(requestID) else {
            return
        }

        let candidates = options.map(\.candidate)
        guard !candidates.isEmpty else {
            return
        }

        let mergedSources = Array(options.map(\.sourcePrimary).uniqued())
        let source = LookupContentSource(
            primary: mergedSources.first ?? .cedict,
            components: Array(mergedSources.dropFirst())
        )

        if let activeLookupHistoryRecordID {
            let previewRecord = LookupHistoryRecord.reverseLookupPreview(
                query: query,
                kind: preferredKind == .phrase ? .phrase : .word,
                candidates: candidates,
                source: source,
                id: activeLookupHistoryRecordID,
                correction: correction,
                status: .completed,
                statusMessage: "已找到 \(candidates.count) 个英文候选。"
            )
            updateLookupHistoryRecord(
                id: activeLookupHistoryRecordID,
                content: previewRecord.content,
                source: previewRecord.source,
                studyAction: previewRecord.studyAction,
                reverseLookupCandidates: previewRecord.reverseLookupCandidates,
                correction: correction,
                status: .completed,
                statusMessage: "已找到 \(candidates.count) 个英文候选。"
            )
        }

        isLookingUp = false
        currentLookupTask = nil
        activeLookupRequestID = nil
        activeLookupHistoryRecordID = nil
        activeLookupSourceContext = nil
        lookupViewState = .candidateSelection(
            query: query,
            kind: preferredKind == .phrase ? .phrase : .word,
            candidates: candidates
        )
        statusMessage = "已找到 \(candidates.count) 个英文候选。继续查词，或者直接送去 Quick Capture / 词库。"
    }

    private func combinedChineseLookupOptions(
        _ optionGroups: [ChineseLookupOption]...
    ) -> [ChineseLookupOption] {
        var merged: [ChineseLookupOption] = []

        for option in optionGroups.flatMap({ $0 }) {
            let optionKind = option.resolvedKind ?? resolvedLookupKind(for: option.candidate.english, preferredKind: .word)
            let key = "\(optionKind.rawValue)::\(option.candidate.english.lowercased())"
            if merged.contains(where: {
                let existingKind = $0.resolvedKind ?? resolvedLookupKind(for: $0.candidate.english, preferredKind: .word)
                let existingKey = "\(existingKind.rawValue)::\($0.candidate.english.lowercased())"
                return existingKey == key
            }) {
                continue
            }

            merged.append(option)
        }

        return Array(merged.prefix(8))
    }

    private func translationLookupOptions(
        chinese: String,
        preferredKind: EntryKind,
        settings _: AppSettings
    ) async -> [ChineseLookupOption] {
        do {
            let translations = try await translateLocally(
                text: chinese,
                direction: .chineseToEnglish
            )
            return normalizedChineseLookupOptions(
                from: translations,
                chinese: chinese,
                preferredKind: preferredKind,
                sourcePrimary: .argos
            )
        } catch {
            return []
        }
    }

    private func aiChineseLookupOptions(
        chinese: String,
        preferredKind: EntryKind,
        settings: AppSettings,
        apiKey: String
    ) async -> [ChineseLookupOption] {
        await lookupService.resolveChineseLookupCandidates(
            chinese: chinese,
            preferredKind: preferredKind,
            settings: settings,
            apiKey: apiKey
        ).map { resolved in
            ChineseLookupOption(
                candidate: ReverseLookupCandidate(
                    english: normalizedEnglishLookupCandidateText(resolved.english),
                    chinese: chinese
                ),
                sourcePrimary: .openAI,
                resolvedKind: resolved.kind,
                modelName: resolved.modelName
            )
        }
    }

    private func normalizedChineseLookupOptions(
        from translations: [String],
        chinese: String,
        preferredKind: EntryKind,
        sourcePrimary: LookupSourceComponentKind
    ) -> [ChineseLookupOption] {
        translations
            .flatMap(splitEnglishTranslationCandidates(from:))
            .map(normalizedEnglishLookupCandidateText(_:))
            .filter { !$0.isEmpty }
            .uniqued()
            .prefix(8)
            .map { english in
                ChineseLookupOption(
                    candidate: ReverseLookupCandidate(
                        english: english,
                        chinese: chinese
                    ),
                    sourcePrimary: sourcePrimary,
                    resolvedKind: resolvedLookupKind(for: english, preferredKind: preferredKind)
                )
            }
    }

    private func splitEnglishTranslationCandidates(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return []
        }

        let separators = CharacterSet(charactersIn: "\n/;；、")
        return normalized
            .components(separatedBy: separators)
            .flatMap { segment in
                segment.components(separatedBy: ",")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedEnglishLookupCandidateText(_ text: String) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’.,!?()[]{}"))

        guard !trimmed.isEmpty else {
            return ""
        }

        let asciiLettersAndSpaces = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ -")
        let isSimpleEnglish = trimmed.unicodeScalars.allSatisfy { asciiLettersAndSpaces.contains($0) }

        if isSimpleEnglish, trimmed == trimmed.capitalized {
            return trimmed.lowercased()
        }

        return trimmed
    }

    private func continueResolvedChineseCandidateLookup(
        _ draft: LookupDraft,
        candidate: ReverseLookupCandidate,
        requestID: UUID,
        correction: LookupCorrection?,
        settings: AppSettings,
        sourcePrimary: LookupSourceComponentKind = .cedict,
        resolvedKind: EntryKind? = nil,
        modelName: String? = nil
    ) async {
        let englishTerm = candidate.english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !englishTerm.isEmpty else {
            await handleChineseTranslationFallback(
                draft,
                requestID: requestID,
                correction: correction,
                settings: settings
            )
            return
        }

        let kind = resolvedKind ?? resolvedLookupKind(for: englishTerm, preferredKind: draft.kind)
        let manifest = settings.offlineResources
        let shellRecord = LookupHistoryRecord(
            originalQuery: draft.trimmedTerm,
            content: LookupContent(
                kind: kind,
                term: englishTerm,
                pronunciation: "",
                partOfSpeech: "",
                meanings: [draft.trimmedTerm],
                meaningGroups: [
                    MeaningGroup(partOfSpeech: "", meanings: [draft.trimmedTerm])
                ],
                examples: [],
                collocations: [],
                translationDirection: .chineseToEnglish
            ),
            source: LookupContentSource(primary: sourcePrimary),
            studyAction: .historyOnly,
            correction: correction
        )

        updateLoadingLookupPreview(
            requestID: requestID,
            query: draft.trimmedTerm,
            fallbackRecord: shellRecord,
            statusMessage: sourcePrimary == .openAI
                ? "已锁定 AI 英文候选，正在补充释义..."
                : "已锁定英文候选，正在补充释义..."
        ) { _ in }

        let quickPreviewTask = Task.detached(priority: .userInitiated) {
            OfflineLexiconService.shared.lookupEnglishQuickPreview(
                term: englishTerm,
                kind: kind,
                manifest: manifest
            )
        }

        Task { [weak self] in
            guard let self else { return }
            guard let core = await quickPreviewTask.value else { return }
            guard !Task.isCancelled else { return }

            self.updateLoadingLookupPreview(
                requestID: requestID,
                query: draft.trimmedTerm,
                fallbackRecord: shellRecord,
                statusMessage: "释义已就绪，正在补充搭配和例句..."
            ) { record in
                record.content.pronunciation = core.pronunciation
                record.content.partOfSpeech = core.partOfSpeech
                record.content.meanings = ([draft.trimmedTerm] + core.meanings).uniqued()
                record.content.meaningGroups = MeaningGroup.normalized(
                    core.meaningGroups,
                    fallbackPartOfSpeech: core.partOfSpeech,
                    fallbackMeanings: ([draft.trimmedTerm] + core.meanings).uniqued(),
                    maxMeanings: EntryCandidateDefaults.meaningChoiceCount
                )
                record.content.englishDefinitions = core.englishDefinitions
                record.content.englishSynonyms = core.englishSynonyms
                record.content.inflectionLines = core.inflectionLines
                record.content.referenceTags = core.referenceTags
                record.source = LookupContentSource(
                    primary: sourcePrimary,
                    components: Array(([sourcePrimary] + core.sourceComponents).uniqued().dropFirst())
                )
            }
        }

        let fallback = await Task.detached(priority: .userInitiated) {
            LookupService().fallbackLookup(term: englishTerm, kind: kind, settings: settings)
        }.value

        guard !Task.isCancelled else {
            return
        }

        let mergedContent = LookupContent(
            kind: fallback.content.kind,
            term: fallback.content.term,
            pronunciation: fallback.content.pronunciation,
            partOfSpeech: fallback.content.partOfSpeech,
            meanings: Array(([draft.trimmedTerm] + fallback.content.meanings).uniqued().prefix(EntryCandidateDefaults.meaningChoiceCount)),
            meaningGroups: MeaningGroup.normalized(
                fallback.content.meaningGroups,
                fallbackPartOfSpeech: fallback.content.partOfSpeech,
                fallbackMeanings: Array(([draft.trimmedTerm] + fallback.content.meanings).uniqued().prefix(EntryCandidateDefaults.meaningChoiceCount)),
                maxMeanings: EntryCandidateDefaults.meaningChoiceCount
            ),
            examples: fallback.content.examples,
            collocations: fallback.content.collocations,
            englishDefinitions: fallback.content.englishDefinitions,
            englishSynonyms: fallback.content.englishSynonyms,
            inflectionLines: fallback.content.inflectionLines,
            referenceTags: fallback.content.referenceTags,
            translationDirection: .chineseToEnglish
        )

        let mergedSource = LookupContentSource(
            primary: sourcePrimary,
            components: Array(([sourcePrimary, fallback.source.primary] + fallback.source.components).uniqued().dropFirst())
        )

        completeLookup(
            requestID: requestID,
            originalQuery: draft.trimmedTerm,
            content: mergedContent,
            source: mergedSource,
            modelName: modelName,
            sourceContext: resolvedLookupSourceContext(for: draft, fallbackToQuery: true),
            correction: correction
        ) { studyAction in
            switch studyAction {
                case .createdDraft:
                    return sourcePrimary == .openAI
                        ? "\"\(draft.trimmedTerm)\" 已解析出英文候选，并已先存成学习草稿。"
                        : "\"\(draft.trimmedTerm)\" 已匹配到英文词，并已先存成学习草稿。"
                case .updatedDraft:
                    return sourcePrimary == .openAI
                        ? "\"\(draft.trimmedTerm)\" 已解析出英文候选，并更新了现有学习草稿。"
                        : "\"\(draft.trimmedTerm)\" 已匹配到英文词，并更新了现有学习草稿。"
            case .alreadyInLibrary:
                return sourcePrimary == .openAI
                    ? "\"\(draft.trimmedTerm)\" 已解析出英文候选；这个词已经在词库里，可继续从词库或 Quick Capture 整理。"
                    : "\"\(draft.trimmedTerm)\" 已匹配到英文词；这个词已经在词库里，可继续从词库或 Quick Capture 整理。"
            case .historyOnly:
                return sourcePrimary == .openAI
                    ? "\"\(draft.trimmedTerm)\" 已解析出英文候选，并记录到历史。接下来可以显式保存到 Quick Capture 或词库。"
                    : "\"\(draft.trimmedTerm)\" 已匹配到英文词，并记录到历史。接下来可以显式保存到 Quick Capture 或词库。"
            case .awaitingCandidateSelection:
                return "请先选择一个英文候选。"
            }
        }
    }

    private func handleSentenceLookup(
        _ draft: LookupDraft,
        originalQuery: String,
        requestID: UUID,
        correction: LookupCorrection?
    ) async {
        let direction: SentenceTranslationDirection = containsChineseCharacters(in: draft.trimmedTerm) ? .chineseToEnglish : .englishToChinese

        do {
            let translations = try await translateLocally(
                text: draft.trimmedTerm,
                direction: direction
            )

            guard isCurrentLookupRequest(requestID) else {
                return
            }

            let examples: [LookupExample]
            switch direction {
            case .englishToChinese:
                examples = [LookupExample(english: draft.trimmedTerm, chinese: translations.first ?? "")]
            case .chineseToEnglish:
                examples = [LookupExample(english: translations.first ?? "", chinese: draft.trimmedTerm)]
            }

            let content = LookupContent(
                kind: .sentence,
                term: direction == .englishToChinese ? draft.trimmedTerm : (translations.first ?? draft.trimmedTerm),
                pronunciation: "",
                partOfSpeech: "句子",
                meanings: Array(translations.prefix(2)),
                examples: examples,
                collocations: [],
                translationDirection: direction
            )

            let studyAction = lookupHistoryAction(for: content)

            let historyRecord = recordLookupHistory(
                originalQuery: originalQuery,
                content: content,
                source: LookupContentSource(primary: .argos),
                studyAction: studyAction,
                correction: correction,
                existingRecordID: activeLookupHistoryRecordID,
                status: .completed,
                statusMessage: nil
            )
            lookupViewState = .success(recordID: historyRecord.id)

            switch studyAction {
            case .createdDraft:
                statusMessage = "英文句子已翻译，并已先存成学习草稿。"
            case .updatedDraft:
                statusMessage = "英文句子已重新翻译，并更新了现有学习草稿。"
            case .historyOnly:
                statusMessage = "句子结果已记录到历史。接下来可以显式保存到 Quick Capture 或词库。"
            case .alreadyInLibrary:
                statusMessage = "这个句子已经在词库里，可继续从词库或 Quick Capture 整理。"
            case .awaitingCandidateSelection:
                statusMessage = "请先选择一个英文候选。"
            }
            currentLookupTask = nil
            activeLookupRequestID = nil
            activeLookupHistoryRecordID = nil
            activeLookupSourceContext = nil
        } catch {
            failLookup(requestID: requestID, query: originalQuery, message: error.localizedDescription)
        }
    }

    private func handleChineseTranslationFallback(
        _ draft: LookupDraft,
        requestID: UUID,
        correction: LookupCorrection?,
        settings: AppSettings
    ) async {
        do {
            let translations = try await translateLocally(
                text: draft.trimmedTerm,
                direction: .chineseToEnglish
            )

            let translationOptions = normalizedChineseLookupOptions(
                from: translations,
                chinese: draft.trimmedTerm,
                preferredKind: draft.kind,
                sourcePrimary: .argos
            )

            if translationOptions.count > 1 {
                presentChineseLookupCandidates(
                    translationOptions,
                    query: draft.trimmedTerm,
                    preferredKind: draft.kind,
                    requestID: requestID,
                    correction: correction
                )
                return
            }

            guard let resolvedOption = translationOptions.first else {
                throw SentenceTranslationServiceError.translationFailed("本地翻译结果为空")
            }

            let primaryTranslation = resolvedOption.candidate.english
            let resolvedKind = resolvedOption.resolvedKind ?? resolvedLookupKind(for: primaryTranslation, preferredKind: draft.kind)
            let shellRecord = LookupHistoryRecord(
                originalQuery: draft.trimmedTerm,
                content: LookupContent(
                    kind: resolvedKind,
                    term: primaryTranslation,
                    pronunciation: "",
                    partOfSpeech: "",
                    meanings: [draft.trimmedTerm],
                    meaningGroups: [
                        MeaningGroup(partOfSpeech: "", meanings: [draft.trimmedTerm])
                    ],
                    examples: [],
                    collocations: [],
                    translationDirection: .chineseToEnglish
                ),
                source: LookupContentSource(primary: .argos),
                studyAction: .historyOnly,
                correction: correction
            )

            updateLoadingLookupPreview(
                requestID: requestID,
                query: draft.trimmedTerm,
                fallbackRecord: shellRecord,
                statusMessage: "已翻成英文，正在补充释义..."
            ) { _ in }

            let offlineLookup = OfflineLexiconService.shared.lookupEnglish(
                term: primaryTranslation,
                kind: resolvedKind,
                manifest: settings.offlineResources
            )

            let mergedMeanings = Array(
                ([draft.trimmedTerm] + (offlineLookup?.meanings ?? []))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .uniqued()
                    .prefix(4)
            )

            let content = LookupContent(
                kind: resolvedKind,
                term: primaryTranslation,
                pronunciation: offlineLookup?.pronunciation ?? "",
                partOfSpeech: offlineLookup?.partOfSpeech ?? (resolvedKind == .phrase ? "短语" : "单词"),
                meanings: mergedMeanings,
                meaningGroups: MeaningGroup.normalized(
                    offlineLookup?.meaningGroups ?? [],
                    fallbackPartOfSpeech: offlineLookup?.partOfSpeech ?? (resolvedKind == .phrase ? "短语" : "单词"),
                    fallbackMeanings: mergedMeanings,
                    maxMeanings: EntryCandidateDefaults.meaningChoiceCount
                ),
                examples: offlineLookup?.examples.isEmpty == false
                    ? (offlineLookup?.examples ?? [])
                    : [LookupExample(english: primaryTranslation, chinese: draft.trimmedTerm)],
                collocations: offlineLookup?.collocations ?? [],
                englishDefinitions: offlineLookup?.englishDefinitions ?? [],
                englishSynonyms: offlineLookup?.englishSynonyms ?? [],
                inflectionLines: offlineLookup?.inflectionLines ?? [],
                referenceTags: offlineLookup?.referenceTags ?? [],
                translationDirection: .chineseToEnglish
            )

            updateLoadingLookupPreview(
                requestID: requestID,
                query: draft.trimmedTerm,
                fallbackRecord: shellRecord,
                statusMessage: "释义已就绪，正在整理结果..."
            ) { record in
                record.content = content
            }

            let sourceComponents = (offlineLookup?.sourceComponents ?? []).filter { $0 != .fallback }
            let source = LookupContentSource(
                primary: .argos,
                components: sourceComponents
            )
            completeLookup(
                requestID: requestID,
                originalQuery: draft.trimmedTerm,
                content: content,
                source: source,
                sourceContext: resolvedLookupSourceContext(for: draft, fallbackToQuery: true),
                correction: correction
            ) { studyAction in
                switch studyAction {
                case .createdDraft:
                    return "\"\(draft.trimmedTerm)\" 已翻成英文，并已先存成学习草稿。"
                case .updatedDraft:
                    return "\"\(draft.trimmedTerm)\" 已重新翻译，并更新了现有学习草稿。"
                case .alreadyInLibrary:
                    return "\"\(draft.trimmedTerm)\" 已翻成英文；这个词已经在词库里，可继续从词库或 Quick Capture 整理。"
                case .historyOnly:
                    return "\"\(draft.trimmedTerm)\" 已翻成英文，并记录到历史。接下来可以显式保存到 Quick Capture 或词库。"
                case .awaitingCandidateSelection:
                    return "请先选择一个英文候选。"
                }
            }
        } catch {
            failLookup(requestID: requestID, query: draft.trimmedTerm, message: error.localizedDescription)
        }
    }

    private func translateLocally(text: String, direction: SentenceTranslationDirection) async throws -> [String] {
        settings.offlineResources.sentenceEngineStatus = .preparing
        settings.offlineResources.sentenceEngineMessage = "正在准备本地句子翻译引擎..."
        persistSettingsSilently()

        let manifest = settings.offlineResources
        let cleanedText = text

        do {
            let translations = try await Task.detached(priority: .userInitiated) {
                try LocalSentenceTranslationService().translate(
                    text: cleanedText,
                    direction: direction,
                    manifest: manifest
                )
            }.value

            settings.offlineResources.sentenceEngineStatus = .ready
            settings.offlineResources.sentenceEngineMessage = "本地句子翻译引擎已就绪。"
            persistSettingsSilently()
            return translations
        } catch {
            settings.offlineResources.sentenceEngineStatus = .failed
            settings.offlineResources.sentenceEngineMessage = error.localizedDescription
            persistSettingsSilently()
            throw error
        }
    }

    private func failLookup(requestID: UUID, query: String, message: String) {
        guard isCurrentLookupRequest(requestID) else {
            return
        }

        if let activeLookupHistoryRecordID {
            updateLookupHistoryRecord(
                id: activeLookupHistoryRecordID,
                status: .failed,
                statusMessage: message
            )
        }

        isLookingUp = false
        lookupViewState = .failure(query: query, message: message)
        latestLookupRecordID = nil
        statusMessage = message
        currentLookupTask = nil
        activeLookupRequestID = nil
        activeLookupHistoryRecordID = nil
        activeLookupSourceContext = nil
    }

    func selectReverseLookupCandidate(_ candidate: ReverseLookupCandidate) {
        lookupDraft.kind = resolvedLookupKind(for: candidate.english, preferredKind: .word)
        lookupDraft.term = candidate.english
        lookupViewState = .loading(
            query: candidate.english,
            previewRecord: nil,
            statusMessage: "正在继续查询英文结果..."
        )
        statusMessage = "已选择 \"\(candidate.english)\"，正在继续查英文结果。"
        lookupCurrentTerm()
    }

    func importOfflineResources(from directory: URL) {
        guard !isImportingOfflineResources else {
            return
        }

        isImportingOfflineResources = true
        offlineResourceStatusMessage = "正在从 \(directory.path) 导入本地词典..."

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let manifest = try await Task.detached(priority: .userInitiated) {
                    let accessed = directory.startAccessingSecurityScopedResource()
                    defer {
                        if accessed {
                            directory.stopAccessingSecurityScopedResource()
                        }
                    }
                    return try OfflineResourcesService().importResources(from: directory)
                }.value
                self.settings.offlineResources = manifest
                self.persistSettingsSilently()
                self.offlineResourceStatusMessage = "本地离线资源已导入。"
                self.statusMessage = "本地词典导入完成。"
                self.scheduleStartupOfflineLexiconEnrichmentIfNeeded(
                    initialEntries: self.entries,
                    initialLookupHistory: self.lookupHistory,
                    manifest: manifest
                )
            } catch {
                self.offlineResourceStatusMessage = error.localizedDescription
                self.statusMessage = "\(error.localizedDescription) 如果你是从桌面默认目录导入失败，请改用“选择文件夹导入”。"
            }

            self.isImportingOfflineResources = false
        }
    }

    private func persistSettingsSilently() {
        var normalizedSettings = settings
        normalizedSettings.normalize()
        normalizedSettings.clearLegacyOpenAIAPIKey()
        settings = normalizedSettings
        try? storage.saveSettings(settings)
    }

    static func containsChineseScalars(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private func containsChineseCharacters(in text: String) -> Bool {
        Self.containsChineseScalars(text)
    }

    private func normalizedLookupSourceContext(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolvedLookupSourceContext(for draft: LookupDraft, fallbackToQuery: Bool = false) -> String? {
        if let activeLookupSourceContext, !activeLookupSourceContext.isEmpty {
            return activeLookupSourceContext
        }

        if let draftSourceContext = normalizedLookupSourceContext(draft.sourceContext) {
            return draftSourceContext
        }

        return fallbackToQuery ? draft.trimmedTerm : nil
    }

    private func resolvedLookupKind(for englishTerm: String, preferredKind: EntryKind) -> EntryKind {
        if preferredKind == .sentence {
            return .sentence
        }

        let cleaned = englishTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains(" ") || cleaned.contains("-") {
            return .phrase
        }

        return .word
    }

    private func cleanSavedArrangements() {
        let validIDs = Set(entries.filter { $0.status == .library }.map(\.id))
        settings.savedLibraryArrangements = settings.savedLibraryArrangements.map { arrangement in
            SavedLibraryArrangement(
                id: arrangement.id,
                name: arrangement.name,
                entryIDs: arrangement.entryIDs.filter { validIDs.contains($0) }
            )
        }

        settings.savedLibraryArrangements.removeAll { $0.entryIDs.isEmpty }

        if !libraryCollectionOptions.contains(where: { $0.id == selectedLibraryCollectionID }) {
            selectedLibraryCollectionID = LibraryCollectionOption.system.id
        }

        do {
            try storage.saveSettings(settings)
        } catch {
            statusMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    private func finishOpenAITest(with result: DraftGenerationResult) {
        isTestingOpenAI = false

        switch result.source {
        case .openAI(let model):
            didLastOpenAITestSucceed = true
            openAITestMessage = "模型 \(model) 测试成功，已成功拿到结构化结果（1 个词性 / 2 个义项 / 2 个例句）。"
            statusMessage = "OpenAI 测试成功。"
        case .localFallback(let kind, _):
            didLastOpenAITestSucceed = false

            switch kind {
            case .aiDisabled:
                openAITestMessage = "测试未执行：AI 生成当前未启用。"
            case .missingAPIKey:
                openAITestMessage = "测试失败：未配置 API key。"
            case .requestFailed:
                let model = result.modelName ?? settings.resolvedOpenAIModel
                let reason = result.fallbackDisplayReason ?? "OpenAI 请求失败"
                openAITestMessage = "模型 \(model) 测试失败：\(reason)"
            }

            statusMessage = openAITestMessage
        }
    }

    private func requestDraftGeneration(for entryID: UUID, trigger: DraftGenerationTrigger) {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return
        }

        cancelGeneration(for: entryID)
        generatingEntryIDs.insert(entryID)

        let term = entry.term
        let sourceContext = entry.sourceContext
        let kind = entry.kind
        let settingsSnapshot = settings
        let apiKeySnapshot = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if case .manualRefresh = trigger {
            statusMessage = "\"\(term)\" 正在生成候选。"
        }

        generationTasks[entryID] = Task { [weak self] in
            guard let self else {
                return
            }

            let result = await self.generator.generateDraft(
                term: term,
                sourceContext: sourceContext,
                kind: kind,
                settings: settingsSnapshot,
                apiKey: apiKeySnapshot
            )

            guard !Task.isCancelled else {
                return
            }

            finishDraftGeneration(result, for: entryID, term: term, trigger: trigger)
        }
    }

    private func finishDraftGeneration(
        _ result: DraftGenerationResult,
        for entryID: UUID,
        term: String,
        trigger: DraftGenerationTrigger
    ) {
        generationTasks[entryID] = nil
        generatingEntryIDs.remove(entryID)

        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        let shouldApply = shouldApplyGeneratedContent(to: entries[index], trigger: trigger)

        recordGenerationMetadata(result, trigger: trigger, forEntryAt: index)

        if shouldApply {
            applyGeneratedContent(result.content, toEntryAt: index)
        }

        entries[index].updatedAt = .now
        persistEntries()
        statusMessage = generationStatusMessage(for: term, result: result, trigger: trigger, applied: shouldApply)
    }

    private func shouldApplyGeneratedContent(to entry: VocabEntry, trigger: DraftGenerationTrigger) -> Bool {
        switch trigger {
        case .capture(let expectedContent):
            return currentGeneratedContent(of: entry) == expectedContent
        case .manualRefresh:
            return true
        }
    }

    private func applyGeneratedContent(_ content: GeneratedEntryContent, toEntryAt index: Int) {
        let mergedMeaningChoices = Self.mergedEntryMeaningChoices(
            incomingChoices: content.meaningChoices,
            existingChoices: entries[index].meaningChoices
        )
        entries[index].partOfSpeech = content.partOfSpeech
        entries[index].meaningChoices = mergedMeaningChoices
        entries[index].meaningGroups = MeaningGroup.normalizedMergedWithFallback(
            content.meaningGroups,
            fallbackPartOfSpeech: content.partOfSpeech,
            fallbackMeanings: mergedMeaningChoices,
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        entries[index].selectedMeaningIndexes = entries[index].meaningChoices.isEmpty ? [] : [0]
        entries[index].generatedExamples = Self.normalizedChoiceEntries(
            content.exampleChoices,
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )
        entries[index].selectedExampleIndexes = entries[index].generatedExamples.isEmpty ? [] : [0]
    }

    private func recordGenerationMetadata(
        _ result: DraftGenerationResult,
        trigger: DraftGenerationTrigger,
        forEntryAt index: Int
    ) {
        entries[index].lastGeneratedAt = .now
        entries[index].lastGenerationSource = generationSource(from: result)
        entries[index].lastGenerationTrigger = trigger.entryGenerationTrigger
        entries[index].lastGenerationModel = result.modelName
        entries[index].lastGenerationFallbackCategory = generationFallbackCategory(from: result)
        entries[index].lastGenerationFailureReason = result.failureReasonForMetadata
    }

    private func currentGeneratedContent(of entry: VocabEntry) -> GeneratedEntryContent {
        GeneratedEntryContent(
            partOfSpeech: entry.partOfSpeech,
            meaningChoices: entry.meaningChoices,
            meaningGroups: entry.meaningGroups,
            exampleChoices: entry.generatedExamples
        )
    }

    private func generationStatusMessage(
        for term: String,
        result: DraftGenerationResult,
        trigger: DraftGenerationTrigger,
        applied: Bool
    ) -> String {
        if !applied {
            return "\"\(term)\" 的新候选已返回，但你已修改当前内容，未自动覆盖。"
        }

        switch result.source {
        case .openAI:
            switch trigger {
            case .capture:
                return "\"\(term)\" 的 AI 候选已补全。"
            case .manualRefresh:
                return "\"\(term)\" 的候选内容已刷新。"
            }
        case .localFallback:
            let suffix = formattedFallbackReason(result.fallbackDisplayReason)
            switch trigger {
            case .capture:
                return "\"\(term)\" 已保留本地候选\(suffix)"
            case .manualRefresh:
                return "\"\(term)\" 已使用本地候选刷新\(suffix)"
            }
        }
    }

    private func formattedFallbackReason(_ reason: String?) -> String {
        guard let reason else {
            return "。"
        }

        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "。"
        }

        return "：\(trimmed)。"
    }

    private func cancelGeneration(for entryID: UUID) {
        generationTasks[entryID]?.cancel()
        generationTasks[entryID] = nil
        generatingEntryIDs.remove(entryID)
    }

    private func generationSource(from result: DraftGenerationResult) -> EntryGenerationSource {
        switch result.source {
        case .openAI:
            return .openAI
        case .localFallback:
            return .fallback
        }
    }

    private func generationFallbackCategory(from result: DraftGenerationResult) -> EntryGenerationFallbackCategory? {
        switch result.fallbackKind {
        case .aiDisabled:
            return .aiDisabled
        case .missingAPIKey:
            return .missingAPIKey
        case .requestFailed:
            return .requestFailed
        case .none:
            return nil
        }
    }

    private func normalizedTerm(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func captureDraftStorageKey(for draft: CaptureDraft) -> String {
        "\(draft.kind.rawValue)::\(normalizedTerm(draft.term))"
    }

    private func matchingCaptureDraft(term: String, kind: EntryKind) -> CaptureDraft? {
        let normalizedCurrentTerm = normalizedTerm(term)
        return savedCaptureDrafts.first(where: {
            $0.kind == kind && normalizedTerm($0.term) == normalizedCurrentTerm
        })
    }

    private func matchingLibraryEntry(term: String, kind: EntryKind) -> VocabEntry? {
        let normalizedCurrentTerm = normalizedTerm(term)
        return libraryEntries.first(where: {
            $0.kind == kind && normalizedTerm($0.term) == normalizedCurrentTerm
        })
    }

    private func seededCaptureDraft(
        term: String,
        kind: EntryKind,
        sourceContext: String?,
        partOfSpeech: String,
        meaningChoices: [String],
        meaningGroups: [MeaningGroup] = [],
        exampleChoices: [String],
        notes: String
    ) -> CaptureDraft {
        let existingDraft = matchingCaptureDraft(term: term, kind: kind)
        let existingLibraryEntry = matchingLibraryEntry(term: term, kind: kind)
        var draft = existingDraft ?? CaptureDraft(
            proficiency: existingLibraryEntry?.proficiency ?? .unknown
        )

        draft.kind = kind
        draft.term = term
        draft.sourceContext = (sourceContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (sourceContext ?? "")
            : (existingDraft?.sourceContext.isEmpty == false
                ? existingDraft?.sourceContext ?? ""
                : (existingLibraryEntry?.sourceContext ?? ""))
        draft.proficiency = existingDraft?.proficiency ?? existingLibraryEntry?.proficiency ?? draft.proficiency

        let fallbackMeanings = existingLibraryEntry?.meaningChoices ?? []
        let nextMeaningChoices = existingDraft?.meaningChoices.isEmpty == false
            ? existingDraft?.meaningChoices ?? []
            : (meaningChoices.isEmpty ? fallbackMeanings : meaningChoices)
        draft.meaningChoices = Self.normalizedChoiceEntries(
            nextMeaningChoices,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        draft.selectedMeaningIndexes = existingDraft?.selectedMeaningIndexes.isEmpty == false
            ? existingDraft?.selectedMeaningIndexes ?? []
            : (draft.meaningChoices.isEmpty ? [] : [0])
        if existingDraft?.meaningCandidates.isEmpty == false {
            draft.meaningCandidates = existingDraft?.meaningCandidates ?? []
        } else {
            draft.meaningCandidates = Self.captureMeaningCandidates(
                meaningGroups: meaningGroups.isEmpty ? (existingLibraryEntry?.meaningGroups ?? []) : meaningGroups,
                fallbackPartOfSpeech: partOfSpeech,
                fallbackMeanings: draft.meaningChoices,
                fallbackSelectedIndexes: draft.selectedMeaningIndexes
            )
        }

        let fallbackExamples = existingLibraryEntry?.generatedExamples ?? []
        let nextExampleChoices = existingDraft?.exampleChoices.isEmpty == false
            ? existingDraft?.exampleChoices ?? []
            : (exampleChoices.isEmpty ? fallbackExamples : exampleChoices)
        draft.exampleChoices = Self.normalizedChoiceEntries(
            nextExampleChoices,
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )
        draft.selectedExampleIndexes = existingDraft?.selectedExampleIndexes.isEmpty == false
            ? existingDraft?.selectedExampleIndexes ?? []
            : (draft.exampleChoices.isEmpty ? [] : [0])

        let existingPartOfSpeech = existingDraft?.partOfSpeech ?? existingLibraryEntry?.partOfSpeech ?? ""
        draft.partOfSpeech = existingPartOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? partOfSpeech
            : existingPartOfSpeech

        let existingNotes = existingDraft?.notes ?? existingLibraryEntry?.notes ?? ""
        draft.notes = existingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? notes
            : existingNotes
        draft.updatedAt = .now
        draft.sanitizeSelections()
        return draft
    }

    private func resolvedCaptureDraft(
        _ draft: CaptureDraft,
        replaceSuggestionFields: Bool
    ) -> CaptureDraft {
        var resolvedDraft = draft
        resolvedDraft.sanitizeSelections()

        let generatedContent = generator.fallbackDraft(
            term: resolvedDraft.trimmedTerm,
            sourceContext: resolvedDraft.trimmedSourceContext,
            kind: resolvedDraft.kind,
            settings: settings
        )

        if replaceSuggestionFields || resolvedDraft.partOfSpeech.isEmpty {
            resolvedDraft.partOfSpeech = generatedContent.partOfSpeech
        }

        if replaceSuggestionFields || resolvedDraft.meaningChoices.isEmpty || resolvedDraft.meaningCandidates.isEmpty {
            resolvedDraft.meaningChoices = Self.normalizedChoiceEntries(
                generatedContent.meaningChoices,
                maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
            )
            resolvedDraft.selectedMeaningIndexes = resolvedDraft.meaningChoices.isEmpty ? [] : [0]
            resolvedDraft.meaningCandidates = Self.captureMeaningCandidates(
                meaningGroups: generatedContent.meaningGroups,
                fallbackPartOfSpeech: generatedContent.partOfSpeech,
                fallbackMeanings: resolvedDraft.meaningChoices,
                fallbackSelectedIndexes: resolvedDraft.selectedMeaningIndexes
            )
        }

        if replaceSuggestionFields || resolvedDraft.exampleChoices.isEmpty {
            resolvedDraft.exampleChoices = Self.normalizedChoiceEntries(
                generatedContent.exampleChoices,
                maxCount: EntryCandidateDefaults.exampleChoiceCount
            )
            resolvedDraft.selectedExampleIndexes = resolvedDraft.exampleChoices.isEmpty ? [] : [0]
        }

        resolvedDraft.updatedAt = .now
        resolvedDraft.sanitizeSelections()
        return resolvedDraft
    }

    private func upsertSavedCaptureDraft(_ draft: CaptureDraft) {
        var nextDraft = draft
        let key = captureDraftStorageKey(for: draft)

        if let existingIndex = savedCaptureDrafts.firstIndex(where: {
            captureDraftStorageKey(for: $0) == key
        }) {
            nextDraft.id = savedCaptureDrafts[existingIndex].id
            nextDraft.createdAt = savedCaptureDrafts[existingIndex].createdAt
            nextDraft.updatedAt = .now
            savedCaptureDrafts[existingIndex] = nextDraft
        } else {
            nextDraft.id = UUID()
            nextDraft.createdAt = .now
            nextDraft.updatedAt = .now
            savedCaptureDrafts.insert(nextDraft, at: 0)
        }

        savedCaptureDrafts.sort { $0.updatedAt > $1.updatedAt }
        persistCaptureDrafts()
    }

    private func upsertRestoredCaptureDraft(_ draft: CaptureDraft) {
        let currentDraft = captureDraft
        upsertSavedCaptureDraft(draft)
        captureDraft = currentDraft
    }

    private func removeSavedCaptureDraft(for draft: CaptureDraft) {
        let key = captureDraftStorageKey(for: draft)
        savedCaptureDrafts.removeAll {
            captureDraftStorageKey(for: $0) == key
        }
        persistCaptureDrafts()
    }

    private func captureSuggestionSeedKey(for term: String, kind: EntryKind) -> String {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedTerm.isEmpty else {
            return ""
        }
        return "\(kind.rawValue)::\(cleanedTerm)"
    }
}

private enum DraftGenerationTrigger {
    case capture(expectedContent: GeneratedEntryContent)
    case manualRefresh

    var entryGenerationTrigger: EntryGenerationTrigger {
        switch self {
        case .capture:
            return .capture
        case .manualRefresh:
            return .manualRefresh
        }
    }
}

private struct ScreenCaptureOCRService: Sendable {
    nonisolated func captureRecognizedText() async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try captureRecognizedTextSynchronously()
        }.value
    }

    nonisolated private func captureRecognizedTextSynchronously() throws -> String {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparrowword-capture-\(UUID().uuidString)")
            .appendingPathExtension("png")

        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", temporaryURL.path]

        do {
            try process.run()
        } catch {
            throw ScreenCaptureOCRError.captureFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ScreenCaptureOCRError.cancelled
        }

        guard FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw ScreenCaptureOCRError.imageUnavailable
        }

        let recognizedText = try recognizedText(from: temporaryURL)
        let normalizedText = recognizedText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else {
            throw ScreenCaptureOCRError.noTextDetected
        }

        return normalizedText
    }

    nonisolated private func recognizedText(from imageURL: URL) throws -> String {
        guard
            let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw ScreenCaptureOCRError.imageUnavailable
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let textCandidates = (request.results ?? [])
            .compactMap { observation -> (CGRect, String)? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }

                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return nil
                }

                return (observation.boundingBox, text)
            }
            .sorted { lhs, rhs in
                let verticalDelta = abs(lhs.0.midY - rhs.0.midY)
                if verticalDelta > 0.03 {
                    return lhs.0.midY > rhs.0.midY
                }

                return lhs.0.minX < rhs.0.minX
            }
            .map(\.1)

        let joinedText = textCandidates.joined(separator: " ")
        guard !joinedText.isEmpty else {
            throw ScreenCaptureOCRError.noTextDetected
        }

        return joinedText
    }
}

private enum ScreenCaptureOCRError: LocalizedError {
    case cancelled
    case captureFailed(String)
    case imageUnavailable
    case noTextDetected

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消截图识词。"
        case .captureFailed(let reason):
            return "截图失败：\(reason)"
        case .imageUnavailable:
            return "没有拿到截图图像。"
        case .noTextDetected:
            return "截图里没有识别到文字。"
        }
    }
}

private struct ChineseLookupOption {
    var candidate: ReverseLookupCandidate
    var sourcePrimary: LookupSourceComponentKind
    var resolvedKind: EntryKind? = nil
    var modelName: String? = nil
}
