import Foundation

enum ProficiencyLevel: Int, Codable, CaseIterable, Identifiable, Comparable {
    case unknown
    case shaky
    case familiar
    case comfortable
    case mastered

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unknown:
            return "不认识"
        case .shaky:
            return "不熟"
        case .familiar:
            return "有印象"
        case .comfortable:
            return "比较熟了"
        case .mastered:
            return "彻底掌握"
        }
    }

    var reviewWeight: Int {
        switch self {
        case .unknown:
            return 5
        case .shaky:
            return 4
        case .familiar:
            return 3
        case .comfortable:
            return 2
        case .mastered:
            return 0
        }
    }

    func upgraded() -> ProficiencyLevel {
        ProficiencyLevel(rawValue: min(rawValue + 1, Self.mastered.rawValue)) ?? self
    }

    func downgraded() -> ProficiencyLevel {
        ProficiencyLevel(rawValue: max(rawValue - 1, Self.unknown.rawValue)) ?? self
    }

    static func < (lhs: ProficiencyLevel, rhs: ProficiencyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum EntryStatus: String, Codable, CaseIterable, Identifiable {
    case inbox
    case library

    var id: String { rawValue }
}

enum EntryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case word
    case phrase
    case sentence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word:
            return "单词"
        case .phrase:
            return "词组"
        case .sentence:
            return "句子"
        }
    }

    var fieldPlaceholder: String {
        switch self {
        case .word:
            return "输入单词"
        case .phrase:
            return "输入词组"
        case .sentence:
            return "输入句子"
        }
    }
}

enum ReviewMode: String, Codable, CaseIterable, Identifiable {
    case meaningToTerm
    case termToMeaning
    case multipleChoice
    case flashcardTermToMeaning
    case flashcardMeaningToTerm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meaningToTerm:
            return "看中文，输入英文"
        case .termToMeaning:
            return "看英文，输入中文"
        case .multipleChoice:
            return "选择题"
        case .flashcardTermToMeaning:
            return "翻卡 · 看英文"
        case .flashcardMeaningToTerm:
            return "翻卡 · 看中文"
        }
    }

    var questionType: ReviewQuestionType {
        switch self {
        case .multipleChoice:
            return .multipleChoice
        case .meaningToTerm, .termToMeaning:
            return .fillIn
        case .flashcardTermToMeaning, .flashcardMeaningToTerm:
            return .flashcards
        }
    }
}

enum ReviewQuestionType: String, Codable, CaseIterable, Identifiable {
    case multipleChoice
    case fillIn
    case flashcards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice:
            return "选择题"
        case .fillIn:
            return "填空题"
        case .flashcards:
            return "翻卡"
        }
    }

    var detail: String {
        switch self {
        case .multipleChoice:
            return "看英文，从选项里挑正确中文。"
        case .fillIn:
            return "看中文，自己打英文；词形对得上就算对。"
        case .flashcards:
            return "点一下卡面就翻开，默认自动升级。"
        }
    }
}

struct ReviewSessionConfiguration: Equatable {
    var questionTypes: [ReviewQuestionType]

    init(questionTypes: [ReviewQuestionType]) {
        let typeSet = Set(questionTypes)
        self.questionTypes = ReviewQuestionType.allCases.filter { typeSet.contains($0) }
    }

    var orderedQuestionTypes: [ReviewQuestionType] {
        questionTypes
    }

    var title: String {
        switch orderedQuestionTypes.count {
        case 0:
            return "未选题型"
        case 1:
            return orderedQuestionTypes[0].title
        default:
            return "随机混刷"
        }
    }

    var detail: String {
        let titles = orderedQuestionTypes.map(\.title)
        switch titles.count {
        case 0:
            return "开始前至少要勾一种题型。"
        case 1:
            return "整轮固定为\(titles[0])。"
        default:
            return "会在 \(titles.joined(separator: "、")) 之间随机出题。"
        }
    }

    var showsMixedQuestionTypes: Bool {
        orderedQuestionTypes.count > 1
    }
}

enum ReviewSourceKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case library
    case favorites
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            return "词库词汇"
        case .favorites:
            return "收藏词汇"
        case .history:
            return "历史词汇"
        }
    }

    var shortTitle: String {
        switch self {
        case .library:
            return "词库"
        case .favorites:
            return "收藏"
        case .history:
            return "历史"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            return "books.vertical"
        case .favorites:
            return "heart.fill"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "inbox":
            self = .history
        case "library":
            self = .library
        case "favorites":
            self = .favorites
        case "history":
            self = .history
        default:
            self = .history
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ReviewSortOption: String, Codable, CaseIterable, Identifiable {
    case priority
    case newestFirst
    case oldestFirst
    case leastRecentlyReviewed
    case alphabetical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priority:
            return "推荐顺序"
        case .newestFirst:
            return "最近加入"
        case .oldestFirst:
            return "最早加入"
        case .leastRecentlyReviewed:
            return "最久没复习"
        case .alphabetical:
            return "英文 A-Z"
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case lookup
    case library
    case review
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lookup:
            return "查词"
        case .library:
            return "词库"
        case .review:
            return "复习"
        case .history:
            return "历史"
        }
    }

    var systemImage: String {
        switch self {
        case .lookup:
            return "magnifyingglass"
        case .library:
            return "books.vertical"
        case .review:
            return "checklist"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

enum WorkspacePaneLayoutPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .horizontal:
            return "左右"
        case .vertical:
            return "上下"
        }
    }

    func title(for language: AppDisplayLanguage) -> String {
        switch self {
        case .automatic:
            return language.text("自动", "Automatic")
        case .horizontal:
            return language.text("左右", "Side by Side")
        case .vertical:
            return language.text("上下", "Top and Bottom")
        }
    }
}

enum ReviewDecision: String, Codable {
    case downgrade
    case keep
    case upgrade

    var title: String {
        switch self {
        case .downgrade:
            return "降级"
        case .keep:
            return "保持"
        case .upgrade:
            return "升级"
        }
    }
}

enum EntryGenerationSource: String, Codable, Equatable {
    case openAI = "OpenAI"
    case fallback = "Fallback"

    var title: String { rawValue }
}

enum EntryGenerationTrigger: String, Codable, Equatable {
    case capture
    case manualRefresh

    var title: String {
        switch self {
        case .capture:
            return "录入生成"
        case .manualRefresh:
            return "手动刷新"
        }
    }
}

enum EntryGenerationFallbackCategory: String, Codable, Equatable {
    case aiDisabled
    case missingAPIKey
    case requestFailed

    var title: String {
        switch self {
        case .aiDisabled:
            return "AI 生成未启用"
        case .missingAPIKey:
            return "未配置 API key"
        case .requestFailed:
            return "OpenAI 请求失败"
        }
    }
}

enum EntrySortCriterion: String, Codable, CaseIterable, Identifiable {
    case proficiency
    case createdAt
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proficiency:
            return "熟练度"
        case .createdAt:
            return "录入时间"
        case .kind:
            return "类型"
        }
    }

    nonisolated var defaultIsAscending: Bool {
        switch self {
        case .proficiency:
            return true
        case .createdAt:
            return false
        case .kind:
            return true
        }
    }
}

enum EntrySortDirection: String, Codable, CaseIterable, Identifiable {
    case ascending
    case descending
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending:
            return "正序"
        case .descending:
            return "倒序"
        case .random:
            return "随机"
        }
    }

    func next() -> EntrySortDirection {
        switch self {
        case .ascending:
            return .descending
        case .descending:
            return .random
        case .random:
            return .ascending
        }
    }
}

struct EntrySortRule: Codable, Equatable, Identifiable {
    var criterion: EntrySortCriterion
    var direction: EntrySortDirection

    var id: String { criterion.rawValue }

    nonisolated init(criterion: EntrySortCriterion, direction: EntrySortDirection) {
        self.criterion = criterion
        self.direction = direction
    }

    nonisolated init(criterion: EntrySortCriterion, isAscending: Bool) {
        self.criterion = criterion
        self.direction = isAscending ? .ascending : .descending
    }

    enum CodingKeys: String, CodingKey {
        case criterion
        case direction
        case isAscending
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        criterion = try container.decode(EntrySortCriterion.self, forKey: .criterion)

        if let direction = try container.decodeIfPresent(EntrySortDirection.self, forKey: .direction) {
            self.direction = direction
        } else {
            let isAscending = try container.decodeIfPresent(Bool.self, forKey: .isAscending) ?? criterion.defaultIsAscending
            self.direction = isAscending ? .ascending : .descending
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(criterion, forKey: .criterion)
        try container.encode(direction, forKey: .direction)
    }
}

struct SavedLibraryArrangement: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var entryIDs: [UUID]

    nonisolated var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LibraryCollectionKind: String, Hashable {
    case system
    case favorites
    case saved
}

struct LibraryCollectionOption: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: LibraryCollectionKind
    let arrangementID: UUID?

    static let system = LibraryCollectionOption(
        id: "system",
        name: "系统词组",
        kind: .system,
        arrangementID: nil
    )

    static let favorites = LibraryCollectionOption(
        id: "favorites",
        name: "收藏词组",
        kind: .favorites,
        arrangementID: nil
    )
}

enum OfflineSentenceEngineStatus: String, Codable, Equatable, Sendable {
    case unavailable
    case preparing
    case ready
    case failed

    nonisolated var title: String {
        switch self {
        case .unavailable:
            return "未安装"
        case .preparing:
            return "准备中"
        case .ready:
            return "已就绪"
        case .failed:
            return "失败"
        }
    }
}

struct OfflineResourceManifest: Codable, Equatable, Sendable {
    var sourceFolderPath: String
    var importedAt: Date?
    var resourcesDirectoryPath: String
    var ecdictDatabasePath: String
    var cedictDatabasePath: String
    var tatoebaDatabasePath: String
    var argosPackagesDirectoryPath: String
    var pythonHelperDirectoryPath: String
    var isECDICTReady: Bool
    var isCEDICTReady: Bool
    var isTatoebaReady: Bool
    var sentenceEngineStatus: OfflineSentenceEngineStatus
    var sentenceEngineMessage: String
    var lexiconEnrichmentVersion: Int

    enum CodingKeys: String, CodingKey {
        case sourceFolderPath
        case importedAt
        case resourcesDirectoryPath
        case ecdictDatabasePath
        case cedictDatabasePath
        case tatoebaDatabasePath
        case argosPackagesDirectoryPath
        case pythonHelperDirectoryPath
        case isECDICTReady
        case isCEDICTReady
        case isTatoebaReady
        case sentenceEngineStatus
        case sentenceEngineMessage
        case lexiconEnrichmentVersion
    }

    nonisolated init(
        sourceFolderPath: String = "",
        importedAt: Date? = nil,
        resourcesDirectoryPath: String = "",
        ecdictDatabasePath: String = "",
        cedictDatabasePath: String = "",
        tatoebaDatabasePath: String = "",
        argosPackagesDirectoryPath: String = "",
        pythonHelperDirectoryPath: String = "",
        isECDICTReady: Bool = false,
        isCEDICTReady: Bool = false,
        isTatoebaReady: Bool = false,
        sentenceEngineStatus: OfflineSentenceEngineStatus = .unavailable,
        sentenceEngineMessage: String = "",
        lexiconEnrichmentVersion: Int = 0
    ) {
        self.sourceFolderPath = sourceFolderPath
        self.importedAt = importedAt
        self.resourcesDirectoryPath = resourcesDirectoryPath
        self.ecdictDatabasePath = ecdictDatabasePath
        self.cedictDatabasePath = cedictDatabasePath
        self.tatoebaDatabasePath = tatoebaDatabasePath
        self.argosPackagesDirectoryPath = argosPackagesDirectoryPath
        self.pythonHelperDirectoryPath = pythonHelperDirectoryPath
        self.isECDICTReady = isECDICTReady
        self.isCEDICTReady = isCEDICTReady
        self.isTatoebaReady = isTatoebaReady
        self.sentenceEngineStatus = sentenceEngineStatus
        self.sentenceEngineMessage = sentenceEngineMessage
        self.lexiconEnrichmentVersion = max(0, lexiconEnrichmentVersion)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceFolderPath = try container.decodeIfPresent(String.self, forKey: .sourceFolderPath) ?? ""
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt)
        resourcesDirectoryPath = try container.decodeIfPresent(String.self, forKey: .resourcesDirectoryPath) ?? ""
        ecdictDatabasePath = try container.decodeIfPresent(String.self, forKey: .ecdictDatabasePath) ?? ""
        cedictDatabasePath = try container.decodeIfPresent(String.self, forKey: .cedictDatabasePath) ?? ""
        tatoebaDatabasePath = try container.decodeIfPresent(String.self, forKey: .tatoebaDatabasePath) ?? ""
        argosPackagesDirectoryPath = try container.decodeIfPresent(String.self, forKey: .argosPackagesDirectoryPath) ?? ""
        pythonHelperDirectoryPath = try container.decodeIfPresent(String.self, forKey: .pythonHelperDirectoryPath) ?? ""
        isECDICTReady = try container.decodeIfPresent(Bool.self, forKey: .isECDICTReady) ?? false
        isCEDICTReady = try container.decodeIfPresent(Bool.self, forKey: .isCEDICTReady) ?? false
        isTatoebaReady = try container.decodeIfPresent(Bool.self, forKey: .isTatoebaReady) ?? false
        sentenceEngineStatus = try container.decodeIfPresent(OfflineSentenceEngineStatus.self, forKey: .sentenceEngineStatus) ?? .unavailable
        sentenceEngineMessage = try container.decodeIfPresent(String.self, forKey: .sentenceEngineMessage) ?? ""
        lexiconEnrichmentVersion = max(0, try container.decodeIfPresent(Int.self, forKey: .lexiconEnrichmentVersion) ?? 0)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceFolderPath, forKey: .sourceFolderPath)
        try container.encodeIfPresent(importedAt, forKey: .importedAt)
        try container.encode(resourcesDirectoryPath, forKey: .resourcesDirectoryPath)
        try container.encode(ecdictDatabasePath, forKey: .ecdictDatabasePath)
        try container.encode(cedictDatabasePath, forKey: .cedictDatabasePath)
        try container.encode(tatoebaDatabasePath, forKey: .tatoebaDatabasePath)
        try container.encode(argosPackagesDirectoryPath, forKey: .argosPackagesDirectoryPath)
        try container.encode(pythonHelperDirectoryPath, forKey: .pythonHelperDirectoryPath)
        try container.encode(isECDICTReady, forKey: .isECDICTReady)
        try container.encode(isCEDICTReady, forKey: .isCEDICTReady)
        try container.encode(isTatoebaReady, forKey: .isTatoebaReady)
        try container.encode(sentenceEngineStatus, forKey: .sentenceEngineStatus)
        try container.encode(sentenceEngineMessage, forKey: .sentenceEngineMessage)
        try container.encode(lexiconEnrichmentVersion, forKey: .lexiconEnrichmentVersion)
    }

    nonisolated var isImported: Bool {
        isECDICTReady || isCEDICTReady || isTatoebaReady || !argosPackagesDirectoryPath.isEmpty
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    nonisolated static let defaultOpenAIModel = "gpt-5-mini"
    nonisolated static let defaultEntrySortRules: [EntrySortRule] = [
        EntrySortRule(criterion: .proficiency, direction: EntrySortCriterion.proficiency.defaultIsAscending ? .ascending : .descending),
        EntrySortRule(criterion: .createdAt, direction: EntrySortCriterion.createdAt.defaultIsAscending ? .ascending : .descending),
        EntrySortRule(criterion: .kind, direction: EntrySortCriterion.kind.defaultIsAscending ? .ascending : .descending)
    ]

    var excludeMasteredFromReview: Bool
    var interfaceLanguage: AppInterfaceLanguage
    var pronunciationVoicePreference: PronunciationVoicePreference
    var workspacePaneLayoutPreference: WorkspacePaneLayoutPreference
    var showLookupReferenceTags: Bool
    var isLibraryCleanMode: Bool
    var isAIGenerationEnabled: Bool
    var openAIModel: String
    var entrySortRules: [EntrySortRule]
    var savedLibraryArrangements: [SavedLibraryArrangement]
    var offlineResources: OfflineResourceManifest
    private(set) var legacyOpenAIAPIKey: String?

    nonisolated init(
        excludeMasteredFromReview: Bool = true,
        interfaceLanguage: AppInterfaceLanguage = .system,
        pronunciationVoicePreference: PronunciationVoicePreference = .automatic,
        workspacePaneLayoutPreference: WorkspacePaneLayoutPreference = .automatic,
        showLookupReferenceTags: Bool = false,
        isLibraryCleanMode: Bool = false,
        isAIGenerationEnabled: Bool = false,
        openAIModel: String = Self.defaultOpenAIModel,
        entrySortRules: [EntrySortRule] = Self.defaultEntrySortRules,
        savedLibraryArrangements: [SavedLibraryArrangement] = [],
        offlineResources: OfflineResourceManifest = OfflineResourceManifest(),
        legacyOpenAIAPIKey: String? = nil
    ) {
        self.excludeMasteredFromReview = excludeMasteredFromReview
        self.interfaceLanguage = interfaceLanguage
        self.pronunciationVoicePreference = pronunciationVoicePreference
        self.workspacePaneLayoutPreference = workspacePaneLayoutPreference
        self.showLookupReferenceTags = showLookupReferenceTags
        self.isLibraryCleanMode = isLibraryCleanMode
        self.isAIGenerationEnabled = isAIGenerationEnabled
        self.openAIModel = openAIModel
        self.entrySortRules = entrySortRules
        self.savedLibraryArrangements = savedLibraryArrangements
        self.offlineResources = offlineResources
        self.legacyOpenAIAPIKey = legacyOpenAIAPIKey
    }

    nonisolated var resolvedOpenAIModel: String {
        let trimmedModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? Self.defaultOpenAIModel : trimmedModel
    }

    nonisolated var trimmedLegacyOpenAIAPIKey: String {
        legacyOpenAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    nonisolated mutating func normalize() {
        openAIModel = resolvedOpenAIModel
        entrySortRules = normalizedSortRules(entrySortRules)
        savedLibraryArrangements = savedLibraryArrangements
            .map { arrangement in
                SavedLibraryArrangement(
                    id: arrangement.id,
                    name: arrangement.trimmedName.isEmpty ? "排列 \(arrangement.id.uuidString.prefix(4))" : arrangement.trimmedName,
                    entryIDs: arrangement.entryIDs.uniqued()
                )
            }
        offlineResources.sentenceEngineMessage = offlineResources.sentenceEngineMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        offlineResources.lexiconEnrichmentVersion = max(0, offlineResources.lexiconEnrichmentVersion)
    }

    nonisolated mutating func clearLegacyOpenAIAPIKey() {
        legacyOpenAIAPIKey = nil
    }

    enum CodingKeys: String, CodingKey {
        case excludeMasteredFromReview
        case interfaceLanguage
        case pronunciationVoicePreference
        case workspacePaneLayoutPreference
        case showLookupReferenceTags
        case isLibraryCleanMode
        case isAIGenerationEnabled
        case openAIAPIKey
        case openAIModel
        case entrySortRules
        case savedLibraryArrangements
        case offlineResources
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        excludeMasteredFromReview = try container.decodeIfPresent(Bool.self, forKey: .excludeMasteredFromReview) ?? true
        interfaceLanguage = try container.decodeIfPresent(AppInterfaceLanguage.self, forKey: .interfaceLanguage) ?? .system
        pronunciationVoicePreference = try container.decodeIfPresent(PronunciationVoicePreference.self, forKey: .pronunciationVoicePreference) ?? .automatic
        workspacePaneLayoutPreference = try container.decodeIfPresent(WorkspacePaneLayoutPreference.self, forKey: .workspacePaneLayoutPreference) ?? .automatic
        showLookupReferenceTags = try container.decodeIfPresent(Bool.self, forKey: .showLookupReferenceTags) ?? false
        isLibraryCleanMode = try container.decodeIfPresent(Bool.self, forKey: .isLibraryCleanMode) ?? false
        isAIGenerationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAIGenerationEnabled) ?? false
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? Self.defaultOpenAIModel
        entrySortRules = try container.decodeIfPresent([EntrySortRule].self, forKey: .entrySortRules) ?? Self.defaultEntrySortRules
        savedLibraryArrangements = try container.decodeIfPresent([SavedLibraryArrangement].self, forKey: .savedLibraryArrangements) ?? []
        offlineResources = try container.decodeIfPresent(OfflineResourceManifest.self, forKey: .offlineResources) ?? OfflineResourceManifest()
        legacyOpenAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey)
        normalize()
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(excludeMasteredFromReview, forKey: .excludeMasteredFromReview)
        try container.encode(interfaceLanguage, forKey: .interfaceLanguage)
        try container.encode(pronunciationVoicePreference, forKey: .pronunciationVoicePreference)
        try container.encode(workspacePaneLayoutPreference, forKey: .workspacePaneLayoutPreference)
        try container.encode(showLookupReferenceTags, forKey: .showLookupReferenceTags)
        try container.encode(isLibraryCleanMode, forKey: .isLibraryCleanMode)
        try container.encode(isAIGenerationEnabled, forKey: .isAIGenerationEnabled)
        try container.encode(openAIModel, forKey: .openAIModel)
        try container.encode(entrySortRules, forKey: .entrySortRules)
        try container.encode(savedLibraryArrangements, forKey: .savedLibraryArrangements)
        try container.encode(offlineResources, forKey: .offlineResources)
    }

    nonisolated private func normalizedSortRules(_ rules: [EntrySortRule]) -> [EntrySortRule] {
        var normalized: [EntrySortRule] = []

        for criterion in EntrySortCriterion.allCases {
            if let existing = rules.first(where: { $0.criterion == criterion }) {
                normalized.append(existing)
            } else {
                normalized.append(
                    EntrySortRule(
                        criterion: criterion,
                        direction: criterion.defaultIsAscending ? .ascending : .descending
                    )
                )
            }
        }

        return normalized.sorted { left, right in
            let leftIndex = rules.firstIndex(where: { $0.criterion == left.criterion }) ?? Int.max
            let rightIndex = rules.firstIndex(where: { $0.criterion == right.criterion }) ?? Int.max
            return leftIndex < rightIndex
        }
    }
}

struct CaptureMeaningCandidate: Codable, Equatable, Identifiable {
    var id = UUID()
    var partOfSpeech = ""
    var meaning = ""
    var isSelected = false

    static func stableID(index: Int) -> UUID {
        let seed = "capture-meaning-candidate-\(index)"
        let hashA = fnv1a64(seed.utf8, seed: 0xcbf29ce484222325)
        let hashB = fnv1a64(seed.utf8.reversed(), seed: 0x84222325cbf29ce4)

        var bytes = [UInt8](repeating: 0, count: 16)
        for offset in 0..<8 {
            bytes[offset] = UInt8((hashA >> UInt64((7 - offset) * 8)) & 0xff)
            bytes[offset + 8] = UInt8((hashB >> UInt64((7 - offset) * 8)) & 0xff)
        }

        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv1a64<S: Sequence>(_ bytes: S, seed: UInt64) -> UInt64 where S.Element == UInt8 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    var trimmedPartOfSpeech: String {
        partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedMeaning: String {
        meaning.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func normalize() {
        partOfSpeech = trimmedPartOfSpeech
        meaning = trimmedMeaning
    }
}

struct CaptureDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var kind: EntryKind = .word
    var term = ""
    var sourceContext = ""
    var proficiency: ProficiencyLevel = .unknown
    var partOfSpeech = ""
    var meaningCandidates: [CaptureMeaningCandidate] = []
    var meaningChoices: [String] = []
    var selectedMeaningIndexes: [Int] = []
    var exampleChoices: [String] = []
    var selectedExampleIndexes: [Int] = []
    var notes = ""

    var trimmedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSourceContext: String {
        sourceContext.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedTerm.isEmpty
    }

    var selectedMeanings: [String] {
        meaningCandidates
            .filter(\.isSelected)
            .map(\.trimmedMeaning)
            .filter { !$0.isEmpty }
    }

    var selectedExamples: [String] {
        selectedExampleIndexes.compactMap { index in
            guard exampleChoices.indices.contains(index) else {
                return nil
            }
            return exampleChoices[index]
        }
    }

    var hasSelectedMeaning: Bool {
        !selectedMeanings.isEmpty
    }

    var hasSelectedExample: Bool {
        !selectedExamples.isEmpty
    }

    var hasAvailableExamples: Bool {
        exampleChoices.isEmpty == false
    }

    mutating func sanitizeSelections() {
        partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        meaningChoices = Self.sanitizedChoiceEntries(
            meaningChoices,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        selectedMeaningIndexes = normalizedSelectionIndexes(
            selectedMeaningIndexes,
            upperBound: meaningChoices.count
        )

        meaningCandidates = Self.normalizedMeaningCandidates(
            meaningCandidates,
            fallbackPartOfSpeech: partOfSpeech,
            fallbackMeanings: meaningChoices,
            fallbackSelectedIndexes: selectedMeaningIndexes,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        meaningChoices = meaningCandidates.map(\.meaning)
        selectedMeaningIndexes = meaningCandidates.enumerated().compactMap { index, candidate in
            candidate.isSelected ? index : nil
        }
        if partOfSpeech.isEmpty {
            partOfSpeech = meaningCandidates.first(where: { !$0.trimmedPartOfSpeech.isEmpty })?.trimmedPartOfSpeech ?? ""
        }

        exampleChoices = Self.sanitizedChoiceEntries(
            exampleChoices,
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )
        selectedExampleIndexes = normalizedSelectionIndexes(
            selectedExampleIndexes,
            upperBound: exampleChoices.count
        )
        if selectedExampleIndexes.isEmpty, !exampleChoices.isEmpty {
            selectedExampleIndexes = [0]
        }
    }

    private func normalizedSelectionIndexes(_ indexes: [Int], upperBound: Int) -> [Int] {
        Array(indexes.filter { (0..<upperBound).contains($0) }.uniqued()).sorted()
    }

    private static func sanitizedChoiceEntries(_ entries: [String], maxCount: Int) -> [String] {
        Array(
            entries
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniqued()
                .prefix(maxCount)
        )
    }

    private static func normalizedMeaningCandidates(
        _ candidates: [CaptureMeaningCandidate],
        fallbackPartOfSpeech: String,
        fallbackMeanings: [String],
        fallbackSelectedIndexes: [Int],
        maxCount: Int
    ) -> [CaptureMeaningCandidate] {
        let baseCandidates: [CaptureMeaningCandidate]
        if candidates.isEmpty {
            baseCandidates = fallbackMeanings.enumerated().map { index, meaning in
                CaptureMeaningCandidate(
                    partOfSpeech: fallbackPartOfSpeech,
                    meaning: meaning,
                    isSelected: fallbackSelectedIndexes.contains(index)
                )
            }
        } else {
            baseCandidates = candidates
        }

        var normalized: [CaptureMeaningCandidate] = []
        var seenKeys = Set<String>()

        for var candidate in baseCandidates {
            candidate.normalize()
            guard !candidate.trimmedMeaning.isEmpty else {
                continue
            }

            let key = "\(candidate.trimmedPartOfSpeech.lowercased())::\(candidate.trimmedMeaning.lowercased())"
            if let existingIndex = normalized.firstIndex(where: {
                "\( $0.trimmedPartOfSpeech.lowercased())::\($0.trimmedMeaning.lowercased())" == key
            }) {
                normalized[existingIndex].isSelected = normalized[existingIndex].isSelected || candidate.isSelected
                continue
            }

            guard seenKeys.insert(key).inserted else {
                continue
            }

            normalized.append(candidate)
            if normalized.count >= maxCount {
                break
            }
        }

        if normalized.isEmpty == false && normalized.contains(where: \.isSelected) == false {
            normalized[0].isSelected = true
        }

        return normalized
    }
}

struct GeneratedEntryContent: Equatable {
    var partOfSpeech: String
    var meaningChoices: [String]
    var meaningGroups: [MeaningGroup]
    var exampleChoices: [String]

    init(
        partOfSpeech: String,
        meaningChoices: [String],
        meaningGroups: [MeaningGroup] = [],
        exampleChoices: [String]
    ) {
        let normalizedGroups = MeaningGroup.normalized(
            meaningGroups,
            fallbackPartOfSpeech: partOfSpeech,
            fallbackMeanings: meaningChoices,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )

        self.partOfSpeech = MeaningGroup.primaryPartOfSpeech(
            from: normalizedGroups,
            fallback: partOfSpeech
        )
        self.meaningChoices = MeaningGroup.flattenedMeanings(
            from: normalizedGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        self.meaningGroups = normalizedGroups
        self.exampleChoices = exampleChoices
    }
}

enum EntryCandidateDefaults {
    nonisolated static let meaningChoiceCount = 4
    nonisolated static let editableMeaningChoiceCount = 5
    nonisolated static let exampleChoiceCount = 3
}

struct MeaningGroup: Codable, Equatable, Identifiable, Sendable {
    var partOfSpeech: String
    var meanings: [String]

    var id: String {
        let key = meanings.joined(separator: "|")
        return "\(partOfSpeech.lowercased())::\(key)"
    }

    init(partOfSpeech: String, meanings: [String]) {
        self.partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        self.meanings = meanings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    static func normalized(
        _ groups: [MeaningGroup],
        fallbackPartOfSpeech: String = "",
        fallbackMeanings: [String] = [],
        maxMeanings: Int? = nil
    ) -> [MeaningGroup] {
        var merged: [MeaningGroup] = []

        func appendGroup(partOfSpeech: String, meanings: [String]) {
            let cleanedPartOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedMeanings = meanings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniqued()

            guard !cleanedMeanings.isEmpty else {
                return
            }

            if let existingIndex = merged.firstIndex(where: {
                $0.partOfSpeech.caseInsensitiveCompare(cleanedPartOfSpeech) == .orderedSame
            }) {
                merged[existingIndex].meanings = Array((merged[existingIndex].meanings + cleanedMeanings).uniqued())
            } else {
                merged.append(MeaningGroup(partOfSpeech: cleanedPartOfSpeech, meanings: cleanedMeanings))
            }
        }

        groups.forEach { appendGroup(partOfSpeech: $0.partOfSpeech, meanings: $0.meanings) }

        if merged.isEmpty {
            appendGroup(partOfSpeech: fallbackPartOfSpeech, meanings: fallbackMeanings)
        }

        guard let maxMeanings, maxMeanings > 0 else {
            return merged
        }

        var limited = merged.map { MeaningGroup(partOfSpeech: $0.partOfSpeech, meanings: []) }
        var nextMeaningIndexes = Array(repeating: 0, count: merged.count)
        var remaining = maxMeanings

        while remaining > 0 {
            var appendedAnyMeaning = false

            for index in merged.indices {
                guard remaining > 0 else {
                    break
                }

                guard nextMeaningIndexes[index] < merged[index].meanings.count else {
                    continue
                }

                limited[index].meanings.append(merged[index].meanings[nextMeaningIndexes[index]])
                nextMeaningIndexes[index] += 1
                remaining -= 1
                appendedAnyMeaning = true
            }

            if !appendedAnyMeaning {
                break
            }
        }

        return limited.filter { !$0.meanings.isEmpty }
    }

    static func normalizedMergedWithFallback(
        _ groups: [MeaningGroup],
        fallbackPartOfSpeech: String = "",
        fallbackMeanings: [String] = [],
        maxMeanings: Int? = nil
    ) -> [MeaningGroup] {
        let cleanedFallbackPartOfSpeech = fallbackPartOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedFallbackMeanings = fallbackMeanings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        var mergedGroups = normalized(
            groups,
            fallbackPartOfSpeech: cleanedFallbackPartOfSpeech,
            maxMeanings: nil
        )

        let groupedMeaningKeys = Set(
            mergedGroups
                .flatMap(\.meanings)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let missingFallbackMeanings = cleanedFallbackMeanings.filter { meaning in
            groupedMeaningKeys.contains(meaning.lowercased()) == false
        }

        if !missingFallbackMeanings.isEmpty {
            mergedGroups.append(
                MeaningGroup(
                    partOfSpeech: cleanedFallbackPartOfSpeech,
                    meanings: missingFallbackMeanings
                )
            )
        }

        return normalized(
            mergedGroups,
            fallbackPartOfSpeech: cleanedFallbackPartOfSpeech,
            fallbackMeanings: cleanedFallbackMeanings,
            maxMeanings: maxMeanings
        )
    }

    static func flattenedMeanings(from groups: [MeaningGroup], maxCount: Int? = nil) -> [String] {
        let flattened = groups
            .flatMap(\.meanings)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        guard let maxCount, maxCount > 0 else {
            return flattened
        }

        return Array(flattened.prefix(maxCount))
    }

    static func primaryPartOfSpeech(from groups: [MeaningGroup], fallback: String = "") -> String {
        let cleanedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.first?.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? groups[0].partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanedFallback
    }

    static func partOfSpeechLabels(for groups: [MeaningGroup], maxCount: Int? = nil) -> [String] {
        var labels = groups.flatMap { group in
            Array(repeating: group.partOfSpeech, count: group.meanings.count)
        }

        guard let maxCount, maxCount > 0 else {
            return labels
        }

        labels = Array(labels.prefix(maxCount))
        return labels
    }
}

struct LookupCorrection: Codable, Equatable, Sendable {
    var originalTerm: String
    var correctedTerm: String
}

enum LookupHistoryStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case cancelled
    case failed

    var title: String {
        switch self {
        case .inProgress:
            return "查询中"
        case .completed:
            return "已完成"
        case .cancelled:
            return "已取消"
        case .failed:
            return "失败"
        }
    }
}

struct MeaningDisplaySection: Equatable, Identifiable {
    var title: String?
    var lines: [String]

    var id: String {
        "\(title ?? "")::\(lines.joined(separator: "|"))"
    }
}

enum DisplayFormatting {
    static func abbreviatedPartOfSpeech(_ raw: String, kind: EntryKind) -> String? {
        if kind == .sentence {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if kind == .phrase || trimmed == "短语" || trimmed.caseInsensitiveCompare("phrase") == .orderedSame {
            return "phr."
        }

        switch trimmed {
        case "名词":
            return "n."
        case "动词":
            return "v."
        case "形容词":
            return "adj."
        case "副词":
            return "adv."
        case "介词":
            return "prep."
        case "代词":
            return "pron."
        case "连词":
            return "conj."
        case "助词":
            return "part."
        case "数词":
            return "num."
        case "量词":
            return "clf."
        case "单词", "词语":
            return nil
        default:
            break
        }

        switch trimmed.lowercased() {
        case "n", "n.", "noun":
            return "n."
        case "v", "v.", "verb":
            return "v."
        case "adj", "adj.", "adjective":
            return "adj."
        case "adv", "adv.", "adverb":
            return "adv."
        case "prep", "prep.", "preposition":
            return "prep."
        case "pron", "pron.", "pronoun":
            return "pron."
        case "conj", "conj.", "conjunction":
            return "conj."
        case "part", "part.", "particle":
            return "part."
        case "num", "num.", "numeral":
            return "num."
        case "clf", "clf.", "classifier":
            return "clf."
        case "phr", "phr.", "phrase":
            return "phr."
        default:
            return nil
        }
    }

    static func meaningLines(
        meanings: [String],
        partOfSpeech: String,
        kind: EntryKind,
        maxLineLength: Int = 20
    ) -> [String] {
        meaningLines(
            meaningGroups: MeaningGroup.normalized(
                [],
                fallbackPartOfSpeech: partOfSpeech,
                fallbackMeanings: meanings,
                maxMeanings: EntryCandidateDefaults.meaningChoiceCount
            ),
            kind: kind,
            maxLineLength: maxLineLength
        )
    }

    static func meaningLines(
        meaningGroups: [MeaningGroup],
        kind: EntryKind,
        maxLineLength: Int = 20
    ) -> [String] {
        let sections = meaningSections(
            meaningGroups: meaningGroups,
            kind: kind,
            maxLineLength: maxLineLength
        )

        return sections.flatMap { section in
            let prefix = abbreviatedPartOfSpeech(section.title ?? "", kind: kind)
            return section.lines.map { applyPrefix(prefix, to: $0) }
        }
    }

    static func meaningSections(
        meaningGroups: [MeaningGroup],
        kind: EntryKind,
        maxLineLength: Int = 20
    ) -> [MeaningDisplaySection] {
        let normalizedGroups = MeaningGroup.normalized(
            meaningGroups,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )

        guard !normalizedGroups.isEmpty else {
            return []
        }

        guard kind != .sentence else {
            return [
                MeaningDisplaySection(
                    title: nil,
                    lines: wrapMeaningLines(normalizedGroups.flatMap(\.meanings), maxLineLength: maxLineLength)
                )
            ]
        }

        return normalizedGroups.map { group in
            MeaningDisplaySection(
                title: group.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : group.partOfSpeech,
                lines: wrapMeaningLines(group.meanings, maxLineLength: maxLineLength)
            )
        }
    }

    static func prefixedMeaningSections(
        meaningGroups: [MeaningGroup],
        kind: EntryKind,
        maxLineLength: Int = 20
    ) -> [MeaningDisplaySection] {
        let sections = meaningSections(
            meaningGroups: meaningGroups,
            kind: kind,
            maxLineLength: maxLineLength
        )

        return sections.map { section in
            let prefix = abbreviatedPartOfSpeech(section.title ?? "", kind: kind)
            return MeaningDisplaySection(
                title: nil,
                lines: section.lines.map { applyPrefix(prefix, to: $0) }
            )
        }
    }

    static func summaryMeaning(
        meanings: [String],
        partOfSpeech: String,
        kind: EntryKind,
        maxLineLength: Int = 24
    ) -> String {
        summaryMeaning(
            meaningGroups: MeaningGroup.normalized(
                [],
                fallbackPartOfSpeech: partOfSpeech,
                fallbackMeanings: meanings,
                maxMeanings: EntryCandidateDefaults.meaningChoiceCount
            ),
            kind: kind,
            maxLineLength: maxLineLength
        )
    }

    static func summaryMeaning(
        meaningGroups: [MeaningGroup],
        kind: EntryKind,
        maxLineLength: Int = 24
    ) -> String {
        meaningLines(
            meaningGroups: meaningGroups,
            kind: kind,
            maxLineLength: maxLineLength
        ).first ?? ""
    }

    static func prefixedMeaning(
        _ meaning: String,
        partOfSpeech: String,
        kind: EntryKind
    ) -> String {
        let cleanedMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedMeaning.isEmpty else {
            return ""
        }

        return applyPrefix(abbreviatedPartOfSpeech(partOfSpeech, kind: kind), to: cleanedMeaning)
    }

    private static func applyPrefix(_ prefix: String?, to text: String) -> String {
        guard let prefix, !prefix.isEmpty else {
            return text
        }

        return "\(prefix) \(text)"
    }

    private static func wrapMeaningLines(_ meanings: [String], maxLineLength: Int) -> [String] {
        let cleanedMeanings = meanings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        guard !cleanedMeanings.isEmpty else {
            return []
        }

        var lines: [String] = []
        var currentLine: [String] = []

        for meaning in cleanedMeanings {
            let candidateLine = (currentLine + [meaning]).joined(separator: "；")
            if currentLine.isEmpty == false, candidateLine.count > maxLineLength {
                lines.append(currentLine.joined(separator: "；"))
                currentLine = [meaning]
            } else {
                currentLine.append(meaning)
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine.joined(separator: "；"))
        }

        return lines
    }
}

enum SentenceTranslationDirection: String, Codable, Equatable, Sendable {
    case englishToChinese
    case chineseToEnglish

    nonisolated var title: String {
        switch self {
        case .englishToChinese:
            return "中文翻译"
        case .chineseToEnglish:
            return "英文翻译"
        }
    }
}

struct LookupExample: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var english: String
    var chinese: String

    nonisolated init(id: UUID = UUID(), english: String, chinese: String) {
        self.id = id
        self.english = english
        self.chinese = chinese
    }
}

struct ReverseLookupCandidate: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var english: String
    var chinese: String
    var pinyin: String

    nonisolated init(id: UUID = UUID(), english: String, chinese: String, pinyin: String = "") {
        self.id = id
        self.english = english
        self.chinese = chinese
        self.pinyin = pinyin
    }
}

struct LookupContent: Codable, Equatable, Sendable {
    var kind: EntryKind
    var term: String
    var pronunciation: String
    var partOfSpeech: String
    var meanings: [String]
    var meaningGroups: [MeaningGroup]
    var examples: [LookupExample]
    var collocations: [String]
    var englishDefinitions: [String]
    var englishSynonyms: [String]
    var inflectionLines: [String]
    var referenceTags: [String]
    var translationDirection: SentenceTranslationDirection?

    init(
        kind: EntryKind,
        term: String,
        pronunciation: String,
        partOfSpeech: String,
        meanings: [String],
        meaningGroups: [MeaningGroup] = [],
        examples: [LookupExample],
        collocations: [String],
        englishDefinitions: [String] = [],
        englishSynonyms: [String] = [],
        inflectionLines: [String] = [],
        referenceTags: [String] = [],
        translationDirection: SentenceTranslationDirection?
    ) {
        let normalizedGroups = MeaningGroup.normalized(
            meaningGroups,
            fallbackPartOfSpeech: partOfSpeech,
            fallbackMeanings: meanings,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )

        self.kind = kind
        self.term = term
        self.pronunciation = pronunciation
        self.partOfSpeech = MeaningGroup.primaryPartOfSpeech(from: normalizedGroups, fallback: partOfSpeech)
        self.meanings = MeaningGroup.flattenedMeanings(
            from: normalizedGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        self.meaningGroups = normalizedGroups
        self.examples = examples
        self.collocations = collocations
        self.englishDefinitions = Self.normalizedSupplementaryText(englishDefinitions)
        self.englishSynonyms = Self.normalizedSupplementaryText(englishSynonyms)
        self.inflectionLines = Self.normalizedSupplementaryText(inflectionLines)
        self.referenceTags = Self.normalizedSupplementaryText(referenceTags)
        self.translationDirection = translationDirection
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case term
        case pronunciation
        case partOfSpeech
        case meanings
        case meaningGroups
        case examples
        case collocations
        case englishDefinitions
        case englishSynonyms
        case inflectionLines
        case referenceTags
        case translationDirection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .word
        let term = try container.decode(String.self, forKey: .term)
        let pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        let partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? ""
        let meanings = try container.decodeIfPresent([String].self, forKey: .meanings) ?? []
        let meaningGroups = try container.decodeIfPresent([MeaningGroup].self, forKey: .meaningGroups) ?? []
        let examples = try container.decodeIfPresent([LookupExample].self, forKey: .examples) ?? []
        let collocations = try container.decodeIfPresent([String].self, forKey: .collocations) ?? []
        let englishDefinitions = try container.decodeIfPresent([String].self, forKey: .englishDefinitions) ?? []
        let englishSynonyms = try container.decodeIfPresent([String].self, forKey: .englishSynonyms) ?? []
        let inflectionLines = try container.decodeIfPresent([String].self, forKey: .inflectionLines) ?? []
        let referenceTags = try container.decodeIfPresent([String].self, forKey: .referenceTags) ?? []
        let translationDirection = try container.decodeIfPresent(SentenceTranslationDirection.self, forKey: .translationDirection)

        self.init(
            kind: kind,
            term: term,
            pronunciation: pronunciation,
            partOfSpeech: partOfSpeech,
            meanings: meanings,
            meaningGroups: meaningGroups,
            examples: examples,
            collocations: collocations,
            englishDefinitions: englishDefinitions,
            englishSynonyms: englishSynonyms,
            inflectionLines: inflectionLines,
            referenceTags: referenceTags,
            translationDirection: translationDirection
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(term, forKey: .term)
        try container.encode(pronunciation, forKey: .pronunciation)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(meanings, forKey: .meanings)
        try container.encode(meaningGroups, forKey: .meaningGroups)
        try container.encode(examples, forKey: .examples)
        try container.encode(collocations, forKey: .collocations)
        try container.encode(englishDefinitions, forKey: .englishDefinitions)
        try container.encode(englishSynonyms, forKey: .englishSynonyms)
        try container.encode(inflectionLines, forKey: .inflectionLines)
        try container.encode(referenceTags, forKey: .referenceTags)
        try container.encodeIfPresent(translationDirection, forKey: .translationDirection)
    }

    private static func normalizedSupplementaryText(_ items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }
}

enum LookupViewState: Equatable {
    case idle
    case loading(query: String, previewRecord: LookupHistoryRecord?, statusMessage: String)
    case candidateSelection(query: String, kind: EntryKind, candidates: [ReverseLookupCandidate])
    case success(recordID: UUID)
    case failure(query: String, message: String)
}

enum LookupSourceComponentKind: String, Codable, Equatable, Hashable, Sendable {
    case openAI
    case ecdict
    case openEnglishWordNet
    case cedict
    case tatoeba
    case argos
    case systemDictionary
    case fallback

    var title: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .ecdict:
            return "ECDICT"
        case .openEnglishWordNet:
            return "Open English WordNet"
        case .cedict:
            return "CC-CEDICT"
        case .tatoeba:
            return "Tatoeba"
        case .argos:
            return "Argos"
        case .systemDictionary:
            return "系统词典"
        case .fallback:
            return "本地回退"
        }
    }
}

struct LookupContentSource: Codable, Equatable, Sendable {
    var primary: LookupSourceComponentKind
    var components: [LookupSourceComponentKind]

    init(primary: LookupSourceComponentKind, components: [LookupSourceComponentKind] = []) {
        self.primary = primary
        self.components = Array(([primary] + components).uniqued())
    }

    var title: String {
        components.map(\.title).joined(separator: " + ")
    }

    enum CodingKeys: String, CodingKey {
        case primary
        case components
    }

    init(from decoder: Decoder) throws {
        if let rawString = try? decoder.singleValueContainer().decode(String.self) {
            switch rawString {
            case "OpenAI":
                self.init(primary: .openAI)
            case "Fallback":
                self.init(primary: .fallback)
            default:
                self.init(primary: LookupSourceComponentKind(rawValue: rawString) ?? .fallback)
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let primary = try container.decode(LookupSourceComponentKind.self, forKey: .primary)
        let components = try container.decodeIfPresent([LookupSourceComponentKind].self, forKey: .components) ?? []
        self.init(primary: primary, components: components)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primary, forKey: .primary)
        try container.encode(components, forKey: .components)
    }
}

enum LookupStudyAction: String, Codable, Equatable, Sendable {
    case createdDraft
    case updatedDraft
    case alreadyInLibrary
    case historyOnly
    case awaitingCandidateSelection

    var title: String {
        switch self {
        case .createdDraft:
            return "已创建学习草稿"
        case .updatedDraft:
            return "已更新学习草稿"
        case .alreadyInLibrary:
            return "该词已在词库中"
        case .historyOnly:
            return "仅记录历史"
        case .awaitingCandidateSelection:
            return "等待你选择英文候选"
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "createdInbox", "createdDraft":
            self = .createdDraft
        case "updatedInbox", "updatedDraft":
            self = .updatedDraft
        case "skippedExistingLibrary", "alreadyInLibrary":
            self = .alreadyInLibrary
        case "awaitingCandidateSelection":
            self = .awaitingCandidateSelection
        case "historyOnly":
            self = .historyOnly
        default:
            self = .historyOnly
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct LookupHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var queriedAt: Date
    var originalQuery: String
    var content: LookupContent
    var source: LookupContentSource
    var modelName: String?
    var studyAction: LookupStudyAction
    var reverseLookupCandidates: [ReverseLookupCandidate]
    var correction: LookupCorrection?
    var status: LookupHistoryStatus
    var statusMessage: String?

    init(
        id: UUID = UUID(),
        queriedAt: Date = .now,
        originalQuery: String,
        content: LookupContent,
        source: LookupContentSource,
        modelName: String? = nil,
        studyAction: LookupStudyAction,
        reverseLookupCandidates: [ReverseLookupCandidate] = [],
        correction: LookupCorrection? = nil,
        status: LookupHistoryStatus = .completed,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.queriedAt = queriedAt
        self.originalQuery = originalQuery
        self.content = content
        self.source = source
        self.modelName = modelName
        self.studyAction = studyAction
        self.reverseLookupCandidates = reverseLookupCandidates
        self.correction = correction
        self.status = status
        self.statusMessage = statusMessage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case queriedAt
        case originalQuery
        case content
        case source
        case modelName
        case studyAction
        case inboxAction
        case reverseLookupCandidates
        case correction
        case status
        case statusMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        queriedAt = try container.decode(Date.self, forKey: .queriedAt)
        originalQuery = try container.decodeIfPresent(String.self, forKey: .originalQuery)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        content = try container.decode(LookupContent.self, forKey: .content)
        source = try container.decode(LookupContentSource.self, forKey: .source)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        studyAction = try container.decodeIfPresent(LookupStudyAction.self, forKey: .studyAction)
            ?? (try container.decodeIfPresent(LookupStudyAction.self, forKey: .inboxAction) ?? .historyOnly)
        reverseLookupCandidates = try container.decodeIfPresent([ReverseLookupCandidate].self, forKey: .reverseLookupCandidates) ?? []
        correction = try container.decodeIfPresent(LookupCorrection.self, forKey: .correction)
        status = try container.decodeIfPresent(LookupHistoryStatus.self, forKey: .status) ?? .completed
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)

        if originalQuery.isEmpty {
            originalQuery = content.term
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(queriedAt, forKey: .queriedAt)
        try container.encode(originalQuery, forKey: .originalQuery)
        try container.encode(content, forKey: .content)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encode(studyAction, forKey: .studyAction)
        try container.encode(reverseLookupCandidates, forKey: .reverseLookupCandidates)
        try container.encodeIfPresent(correction, forKey: .correction)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(statusMessage, forKey: .statusMessage)
    }

    static func reverseLookupPreview(
        query: String,
        kind: EntryKind,
        candidates: [ReverseLookupCandidate],
        source: LookupContentSource = LookupContentSource(primary: .cedict),
        id: UUID = UUID(),
        queriedAt: Date = .now,
        correction: LookupCorrection? = nil,
        status: LookupHistoryStatus = .completed,
        statusMessage: String? = nil
    ) -> LookupHistoryRecord {
        LookupHistoryRecord(
            id: id,
            queriedAt: queriedAt,
            originalQuery: query,
            content: LookupContent(
                kind: kind,
                term: query,
                pronunciation: "",
                partOfSpeech: "中文反查",
                meanings: [],
                meaningGroups: [],
                examples: [],
                collocations: [],
                translationDirection: nil
            ),
            source: source,
            studyAction: .awaitingCandidateSelection,
            reverseLookupCandidates: candidates,
            correction: correction,
            status: status,
            statusMessage: statusMessage
        )
    }
}

enum TrashSourceCategory: String, Codable, CaseIterable, Identifiable {
    case captureDraft
    case library
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureDraft:
            return "Quick Capture 草稿删除"
        case .library:
            return "词库删除"
        case .history:
            return "历史删除"
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "inbox", "captureDraft":
            self = .captureDraft
        case "library":
            self = .library
        case "history":
            self = .history
        default:
            self = .library
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct TrashItem: Codable, Equatable, Identifiable {
    let id: UUID
    var deletedAt: Date
    var sourceCategory: TrashSourceCategory
    var entry: VocabEntry?
    var historyRecord: LookupHistoryRecord?

    init(id: UUID = UUID(), deletedAt: Date = .now, entry: VocabEntry) {
        self.id = id
        self.deletedAt = deletedAt
        self.sourceCategory = entry.status == .inbox ? .captureDraft : .library
        self.entry = entry
        self.historyRecord = nil
    }

    init(id: UUID = UUID(), deletedAt: Date = .now, historyRecord: LookupHistoryRecord) {
        self.id = id
        self.deletedAt = deletedAt
        self.sourceCategory = .history
        self.entry = nil
        self.historyRecord = historyRecord
    }

    var term: String {
        if let entry {
            return entry.term
        }

        return historyRecord?.content.term ?? ""
    }

    var detailText: String {
        if let entry {
            return DisplayFormatting.prefixedMeaning(
                entry.preferredMeaning,
                partOfSpeech: entry.preferredMeaningPartOfSpeech,
                kind: entry.kind
            )
        }

        guard let historyRecord else {
            return ""
        }

        if historyRecord.originalQuery != historyRecord.content.term {
            return historyRecord.originalQuery
        }

        return DisplayFormatting.summaryMeaning(
            meaningGroups: historyRecord.content.meaningGroups,
            kind: historyRecord.content.kind
        )
    }

    var metadataText: String {
        if let entry {
            return entry.kind.title
        }

        return historyRecord?.content.kind.title ?? ""
    }
}

struct LookupDraft: Equatable {
    var kind: EntryKind = .word
    var term = ""
    var sourceContext = ""

    var trimmedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSourceContext: String {
        sourceContext.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedTerm.isEmpty
    }
}

enum LookupSuggestionReason: String, Equatable, Sendable {
    case inflection
    case prefix
    case phraseExpansion

    var title: String {
        switch self {
        case .inflection:
            return "词形"
        case .prefix:
            return "联想"
        case .phraseExpansion:
            return "短语"
        }
    }
}

struct LookupSuggestion: Identifiable, Equatable, Sendable {
    var term: String
    var preview: String
    var reason: LookupSuggestionReason
    var kind: EntryKind

    var id: String {
        "\(kind.rawValue)::\(reason.rawValue)::\(term.lowercased())"
    }
}

struct ReviewAnswerDraft: Equatable {
    var typedAnswer = ""
    var selectedChoice = ""
    var answerSubmitted = false

    mutating func reset() {
        typedAnswer = ""
        selectedChoice = ""
        answerSubmitted = false
    }
}

struct VocabEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var kind: EntryKind
    var term: String
    var sourceContext: String
    var proficiency: ProficiencyLevel
    var status: EntryStatus
    var partOfSpeech: String
    var meaningChoices: [String]
    var meaningGroups: [MeaningGroup]
    var selectedMeaningIndexes: [Int]
    var generatedExamples: [String]
    var selectedExampleIndexes: [Int]
    var englishDefinitions: [String]
    var englishSynonyms: [String]
    var inflectionLines: [String]
    var referenceTags: [String]
    var notes: String
    var isFavorite: Bool
    var reviewCount: Int
    var lastReviewedAt: Date?
    var lastGeneratedAt: Date? = nil
    var lastGenerationSource: EntryGenerationSource? = nil
    var lastGenerationTrigger: EntryGenerationTrigger? = nil
    var lastGenerationModel: String? = nil
    var lastGenerationFallbackCategory: EntryGenerationFallbackCategory? = nil
    var lastGenerationFailureReason: String? = nil

    private var normalizedMeaningSelectionIndexes: [Int] {
        normalizedSelectionIndexes(selectedMeaningIndexes, upperBound: meaningChoices.count)
    }

    private var normalizedExampleSelectionIndexes: [Int] {
        normalizedSelectionIndexes(selectedExampleIndexes, upperBound: generatedExamples.count)
    }

    private var selectedNonEmptyMeaningIndexes: [Int] {
        normalizedMeaningSelectionIndexes.filter { index in
            meaningChoices[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private var selectedNonEmptyExampleIndexes: [Int] {
        normalizedExampleSelectionIndexes.filter { index in
            generatedExamples[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    var preferredMeaning: String {
        guard let index = selectedNonEmptyMeaningIndexes.first ?? meaningChoices.indices.first else {
            return ""
        }

        return meaningChoices[index]
    }

    var preferredMeaningPartOfSpeech: String {
        guard let index = selectedNonEmptyMeaningIndexes.first ?? meaningChoices.indices.first else {
            return partOfSpeech
        }

        return partOfSpeechForMeaningChoice(at: index)
    }

    var selectedMeanings: [String] {
        selectedNonEmptyMeaningIndexes.map { meaningChoices[$0] }
    }

    var normalizedMeaningGroups: [MeaningGroup] {
        MeaningGroup.normalizedMergedWithFallback(
            meaningGroups,
            fallbackPartOfSpeech: partOfSpeech,
            fallbackMeanings: meaningChoices,
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )
    }

    var meaningChoicePartOfSpeechLabels: [String] {
        MeaningGroup.partOfSpeechLabels(
            for: normalizedMeaningGroups,
            maxCount: meaningChoices.count
        )
    }

    var meaningCandidates: [CaptureMeaningCandidate] {
        let groups = meaningGroups.isEmpty
            ? MeaningGroup.normalized(
                [],
                fallbackPartOfSpeech: partOfSpeech,
                fallbackMeanings: meaningChoices,
                maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
            )
            : MeaningGroup.normalizedMergedWithFallback(
                meaningGroups,
                fallbackPartOfSpeech: partOfSpeech,
                fallbackMeanings: meaningChoices,
                maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
            )

        let labels = MeaningGroup.partOfSpeechLabels(
            for: groups,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        let flattened = MeaningGroup.flattenedMeanings(
            from: groups,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        let selectedSet = Set(selectedMeanings.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        return flattened.enumerated().map { index, meaning in
            CaptureMeaningCandidate(
                id: CaptureMeaningCandidate.stableID(
                    index: index
                ),
                partOfSpeech: labels.indices.contains(index) ? labels[index] : partOfSpeech,
                meaning: meaning,
                isSelected: selectedSet.contains(
                    meaning.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            )
        }
    }

    func partOfSpeechForMeaningChoice(at index: Int) -> String {
        guard meaningChoicePartOfSpeechLabels.indices.contains(index) else {
            return partOfSpeech
        }

        let label = meaningChoicePartOfSpeechLabels[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? partOfSpeech : label
    }

    var selectedGeneratedExample: String? {
        guard let selectedExampleIndex = selectedNonEmptyExampleIndexes.first else {
            return nil
        }

        return generatedExamples[selectedExampleIndex]
    }

    var hasSelectedMeaning: Bool {
        !selectedNonEmptyMeaningIndexes.isEmpty
    }

    var hasSelectedExample: Bool {
        !selectedNonEmptyExampleIndexes.isEmpty
    }

    var hasAvailableExamples: Bool {
        generatedExamples.contains { entry in
            entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    mutating func sanitizeSelections() {
        normalizeMeaningData()
        selectedMeaningIndexes = normalizedMeaningSelectionIndexes
        selectedExampleIndexes = normalizedExampleSelectionIndexes
    }

    mutating func applyMeaningCandidates(_ candidates: [CaptureMeaningCandidate]) {
        let normalizedCandidates = candidates
            .map { candidate -> CaptureMeaningCandidate in
                var copy = candidate
                copy.normalize()
                return copy
            }
            .filter { !$0.trimmedMeaning.isEmpty }

        guard !normalizedCandidates.isEmpty else {
            meaningGroups = []
            meaningChoices = []
            selectedMeaningIndexes = []
            partOfSpeech = ""
            sanitizeSelections()
            return
        }

        let groups = MeaningGroup.normalizedMergedWithFallback(
            normalizedCandidates.map { candidate in
                MeaningGroup(
                    partOfSpeech: candidate.trimmedPartOfSpeech.isEmpty ? partOfSpeech : candidate.trimmedPartOfSpeech,
                    meanings: [candidate.trimmedMeaning]
                )
            },
            fallbackPartOfSpeech: partOfSpeech,
            fallbackMeanings: normalizedCandidates.map(\.meaning),
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )

        let flattened = MeaningGroup.flattenedMeanings(
            from: groups,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        let selected = normalizedCandidates.filter(\.isSelected).map(\.meaning)

        meaningGroups = groups
        meaningChoices = flattened
        selectedMeaningIndexes = Self.remappedMeaningSelectionIndexes(selected, in: flattened)
        partOfSpeech = MeaningGroup.primaryPartOfSpeech(from: groups, fallback: partOfSpeech)
        sanitizeSelections()
    }

    var reviewPromptHint: String {
        switch proficiency {
        case .unknown:
            return "先认熟意思，再进入输出。"
        case .shaky:
            return "开始从识别转向输出。"
        case .familiar:
            return "已经有印象，建议多练输入。"
        case .comfortable:
            return "比较熟了，优先打字回忆。"
        case .mastered:
            return "默认不进入复习队列。"
        }
    }

    var lastGenerationReasonDescription: String? {
        guard lastGenerationSource == .fallback else {
            return nil
        }

        switch lastGenerationFallbackCategory {
        case .aiDisabled:
            return EntryGenerationFallbackCategory.aiDisabled.title
        case .missingAPIKey:
            return EntryGenerationFallbackCategory.missingAPIKey.title
        case .requestFailed:
            let reason = lastGenerationFailureReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return reason.isEmpty ? EntryGenerationFallbackCategory.requestFailed.title : reason
        case .none:
            return nil
        }
    }

    private func normalizedSelectionIndexes(_ indexes: [Int], upperBound: Int) -> [Int] {
        Array(indexes.filter { (0..<upperBound).contains($0) }.uniqued()).sorted()
    }

    private static func remappedMeaningSelectionIndexes(_ selectedMeanings: [String], in choices: [String]) -> [Int] {
        var usedIndexes = Set<Int>()
        let remapped = selectedMeanings.compactMap { selectedMeaning -> Int? in
            let cleanedSelection = selectedMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedSelection.isEmpty else {
                return nil
            }

            guard let matchedIndex = choices.indices.first(where: { index in
                guard !usedIndexes.contains(index) else {
                    return false
                }

                return choices[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(cleanedSelection) == .orderedSame
            }) else {
                return nil
            }

            usedIndexes.insert(matchedIndex)
            return matchedIndex
        }

        if !remapped.isEmpty {
            return remapped
        }

        return choices.isEmpty ? [] : [0]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case kind
        case term
        case sourceContext
        case proficiency
        case status
        case partOfSpeech
        case meaningChoices
        case meaningGroups
        case preferredMeaningIndex
        case selectedMeaningIndexes
        case generatedExamples
        case selectedExampleIndex
        case selectedExampleIndexes
        case englishDefinitions
        case englishSynonyms
        case inflectionLines
        case referenceTags
        case notes
        case isFavorite
        case reviewCount
        case lastReviewedAt
        case lastGeneratedAt
        case lastGenerationSource
        case lastGenerationTrigger
        case lastGenerationModel
        case lastGenerationFallbackCategory
        case lastGenerationFailureReason
    }

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        kind: EntryKind,
        term: String,
        sourceContext: String,
        proficiency: ProficiencyLevel,
        status: EntryStatus,
        partOfSpeech: String,
        meaningChoices: [String],
        meaningGroups: [MeaningGroup] = [],
        selectedMeaningIndexes: [Int],
        generatedExamples: [String],
        selectedExampleIndexes: [Int],
        englishDefinitions: [String] = [],
        englishSynonyms: [String] = [],
        inflectionLines: [String] = [],
        referenceTags: [String] = [],
        notes: String,
        isFavorite: Bool,
        reviewCount: Int,
        lastReviewedAt: Date?,
        lastGeneratedAt: Date? = nil,
        lastGenerationSource: EntryGenerationSource? = nil,
        lastGenerationTrigger: EntryGenerationTrigger? = nil,
        lastGenerationModel: String? = nil,
        lastGenerationFallbackCategory: EntryGenerationFallbackCategory? = nil,
        lastGenerationFailureReason: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.term = term
        self.sourceContext = sourceContext
        self.proficiency = proficiency
        self.status = status
        self.partOfSpeech = partOfSpeech
        self.meaningChoices = meaningChoices
        self.meaningGroups = meaningGroups
        self.selectedMeaningIndexes = selectedMeaningIndexes
        self.generatedExamples = generatedExamples
        self.selectedExampleIndexes = selectedExampleIndexes
        self.englishDefinitions = Self.normalizedSupplementaryText(englishDefinitions)
        self.englishSynonyms = Self.normalizedSupplementaryText(englishSynonyms)
        self.inflectionLines = Self.normalizedSupplementaryText(inflectionLines)
        self.referenceTags = Self.normalizedSupplementaryText(referenceTags)
        self.notes = notes
        self.isFavorite = isFavorite
        self.reviewCount = reviewCount
        self.lastReviewedAt = lastReviewedAt
        self.lastGeneratedAt = lastGeneratedAt
        self.lastGenerationSource = lastGenerationSource
        self.lastGenerationTrigger = lastGenerationTrigger
        self.lastGenerationModel = lastGenerationModel
        self.lastGenerationFallbackCategory = lastGenerationFallbackCategory
        self.lastGenerationFailureReason = lastGenerationFailureReason
        sanitizeSelections()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        kind = try container.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .word
        term = try container.decode(String.self, forKey: .term)
        sourceContext = try container.decode(String.self, forKey: .sourceContext)
        proficiency = try container.decode(ProficiencyLevel.self, forKey: .proficiency)
        status = try container.decode(EntryStatus.self, forKey: .status)
        partOfSpeech = try container.decode(String.self, forKey: .partOfSpeech)
        meaningChoices = try container.decode([String].self, forKey: .meaningChoices)
        meaningGroups = try container.decodeIfPresent([MeaningGroup].self, forKey: .meaningGroups) ?? []

        if let selectedMeaningIndexes = try container.decodeIfPresent([Int].self, forKey: .selectedMeaningIndexes) {
            self.selectedMeaningIndexes = selectedMeaningIndexes
        } else if let preferredMeaningIndex = try container.decodeIfPresent(Int.self, forKey: .preferredMeaningIndex) {
            self.selectedMeaningIndexes = [preferredMeaningIndex]
        } else {
            self.selectedMeaningIndexes = meaningChoices.isEmpty ? [] : [0]
        }

        generatedExamples = try container.decode([String].self, forKey: .generatedExamples)

        if let selectedExampleIndexes = try container.decodeIfPresent([Int].self, forKey: .selectedExampleIndexes) {
            self.selectedExampleIndexes = selectedExampleIndexes
        } else if let selectedExampleIndex = try container.decodeIfPresent(Int.self, forKey: .selectedExampleIndex) {
            self.selectedExampleIndexes = [selectedExampleIndex]
        } else {
            self.selectedExampleIndexes = generatedExamples.isEmpty ? [] : [0]
        }

        englishDefinitions = try container.decodeIfPresent([String].self, forKey: .englishDefinitions) ?? []
        englishSynonyms = try container.decodeIfPresent([String].self, forKey: .englishSynonyms) ?? []
        inflectionLines = try container.decodeIfPresent([String].self, forKey: .inflectionLines) ?? []
        referenceTags = try container.decodeIfPresent([String].self, forKey: .referenceTags) ?? []
        notes = try container.decode(String.self, forKey: .notes)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        reviewCount = try container.decode(Int.self, forKey: .reviewCount)
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        lastGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .lastGeneratedAt)
        lastGenerationSource = try container.decodeIfPresent(EntryGenerationSource.self, forKey: .lastGenerationSource)
        lastGenerationTrigger = try container.decodeIfPresent(EntryGenerationTrigger.self, forKey: .lastGenerationTrigger)
        lastGenerationModel = try container.decodeIfPresent(String.self, forKey: .lastGenerationModel)
        lastGenerationFallbackCategory = try container.decodeIfPresent(EntryGenerationFallbackCategory.self, forKey: .lastGenerationFallbackCategory)
        lastGenerationFailureReason = try container.decodeIfPresent(String.self, forKey: .lastGenerationFailureReason)
        sanitizeSelections()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(kind, forKey: .kind)
        try container.encode(term, forKey: .term)
        try container.encode(sourceContext, forKey: .sourceContext)
        try container.encode(proficiency, forKey: .proficiency)
        try container.encode(status, forKey: .status)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(meaningChoices, forKey: .meaningChoices)
        try container.encode(meaningGroups, forKey: .meaningGroups)
        try container.encode(selectedMeaningIndexes, forKey: .selectedMeaningIndexes)
        try container.encode(selectedMeaningIndexes.first ?? 0, forKey: .preferredMeaningIndex)
        try container.encode(generatedExamples, forKey: .generatedExamples)
        try container.encode(selectedExampleIndexes, forKey: .selectedExampleIndexes)
        try container.encodeIfPresent(selectedExampleIndexes.first, forKey: .selectedExampleIndex)
        try container.encode(englishDefinitions, forKey: .englishDefinitions)
        try container.encode(englishSynonyms, forKey: .englishSynonyms)
        try container.encode(inflectionLines, forKey: .inflectionLines)
        try container.encode(referenceTags, forKey: .referenceTags)
        try container.encode(notes, forKey: .notes)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(reviewCount, forKey: .reviewCount)
        try container.encodeIfPresent(lastReviewedAt, forKey: .lastReviewedAt)
        try container.encodeIfPresent(lastGeneratedAt, forKey: .lastGeneratedAt)
        try container.encodeIfPresent(lastGenerationSource, forKey: .lastGenerationSource)
        try container.encodeIfPresent(lastGenerationTrigger, forKey: .lastGenerationTrigger)
        try container.encodeIfPresent(lastGenerationModel, forKey: .lastGenerationModel)
        try container.encodeIfPresent(lastGenerationFallbackCategory, forKey: .lastGenerationFallbackCategory)
        try container.encodeIfPresent(lastGenerationFailureReason, forKey: .lastGenerationFailureReason)
    }

    private mutating func normalizeMeaningData() {
        let cleanedChoices = meaningChoices
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        let normalizedGroups = MeaningGroup.normalized(
            meaningGroups,
            fallbackPartOfSpeech: partOfSpeech,
            fallbackMeanings: cleanedChoices,
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )

        let reconciledGroups = MeaningGroup.normalizedMergedWithFallback(
            normalizedGroups,
            fallbackPartOfSpeech: partOfSpeech,
            fallbackMeanings: cleanedChoices,
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )

        meaningGroups = reconciledGroups
        meaningChoices = MeaningGroup.flattenedMeanings(
            from: reconciledGroups,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )

        partOfSpeech = MeaningGroup.primaryPartOfSpeech(from: meaningGroups, fallback: partOfSpeech)
        englishDefinitions = Self.normalizedSupplementaryText(englishDefinitions)
        englishSynonyms = Self.normalizedSupplementaryText(englishSynonyms)
        inflectionLines = Self.normalizedSupplementaryText(inflectionLines)
        referenceTags = Self.normalizedSupplementaryText(referenceTags)
    }

    private static func normalizedSupplementaryText(_ items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }
}

struct ReviewCard: Equatable {
    let entryID: UUID
    let mode: ReviewMode
    let prompt: String
    let promptTitle: String
    let answer: String
    let distractors: [String]
    let acceptedAnswers: [String]

    var isFlashcardMode: Bool {
        switch mode {
        case .flashcardTermToMeaning, .flashcardMeaningToTerm:
            return true
        case .meaningToTerm, .termToMeaning, .multipleChoice:
            return false
        }
    }

    var questionType: ReviewQuestionType {
        mode.questionType
    }

    func matchesSubmittedAnswer(_ submission: String) -> Bool {
        let trimmedSubmission = submission.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSubmission.isEmpty == false else {
            return false
        }

        return acceptedAnswers.contains { accepted in
            Self.answersMatch(trimmedSubmission, accepted: accepted)
        }
    }

    private static func answersMatch(_ submission: String, accepted: String) -> Bool {
        let normalizedSubmission = normalizedComparableText(submission)
        let normalizedAccepted = normalizedComparableText(accepted)

        guard normalizedSubmission.isEmpty == false, normalizedAccepted.isEmpty == false else {
            return false
        }

        if normalizedSubmission == normalizedAccepted {
            return true
        }

        if englishPhrasesEquivalent(normalizedSubmission, normalizedAccepted) {
            return true
        }

        let acceptedSegments = answerSegments(from: normalizedAccepted)
        let submissionSegments = answerSegments(from: normalizedSubmission)

        if acceptedSegments.contains(normalizedSubmission) || submissionSegments.contains(normalizedAccepted) {
            return true
        }

        if acceptedSegments.count > 1 {
            return acceptedSegments.contains { segment in
                segment == normalizedSubmission || englishPhrasesEquivalent(normalizedSubmission, segment)
            }
        }

        if submissionSegments.count > 1 {
            return submissionSegments.contains { segment in
                segment == normalizedAccepted || englishPhrasesEquivalent(segment, normalizedAccepted)
            }
        }

        return false
    }

    private static func normalizedComparableText(_ text: String) -> String {
        let lowered = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet(charactersIn: "-'").contains(scalar) {
                return Character(scalar)
            }

            return " "
        }

        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func answerSegments(from text: String) -> [String] {
        let separatorSet = CharacterSet(charactersIn: ",;/|，；、")

        return text
            .components(separatedBy: separatorSet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private static func englishPhrasesEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        guard containsLatinLetters(lhs), containsLatinLetters(rhs) else {
            return false
        }

        let leftTokens = lhs.split(separator: " ").map(String.init)
        let rightTokens = rhs.split(separator: " ").map(String.init)

        guard leftTokens.count == rightTokens.count, leftTokens.isEmpty == false else {
            return false
        }

        return zip(leftTokens, rightTokens).allSatisfy { leftToken, rightToken in
            englishTokenVariants(leftToken).intersection(englishTokenVariants(rightToken)).isEmpty == false
        }
    }

    private static func containsLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.value < 128 }
    }

    private static func englishTokenVariants(_ token: String) -> Set<String> {
        var variants: Set<String> = [token]
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "-'"))
        variants.insert(cleaned)

        guard cleaned.isEmpty == false else {
            return variants
        }

        let irregulars: [String: [String]] = [
            "am": ["be"],
            "are": ["be"],
            "is": ["be"],
            "was": ["be"],
            "were": ["be"],
            "been": ["be"],
            "went": ["go"],
            "gone": ["go"],
            "did": ["do"],
            "done": ["do"],
            "had": ["have"],
            "has": ["have"],
            "having": ["have"],
            "better": ["good"],
            "best": ["good"],
            "worse": ["bad"],
            "worst": ["bad"],
            "children": ["child"],
            "men": ["man"],
            "women": ["woman"],
            "mice": ["mouse"],
            "geese": ["goose"],
            "teeth": ["tooth"],
            "feet": ["foot"]
        ]

        if let mapped = irregulars[cleaned] {
            variants.formUnion(mapped)
        }

        if cleaned.hasSuffix("'s"), cleaned.count > 2 {
            variants.insert(String(cleaned.dropLast(2)))
        }

        if cleaned.hasSuffix("ies"), cleaned.count > 3 {
            variants.insert(String(cleaned.dropLast(3)) + "y")
        }

        if cleaned.hasSuffix("es"), cleaned.count > 3 {
            variants.insert(String(cleaned.dropLast(2)))
        }

        if cleaned.hasSuffix("s"), cleaned.count > 2 {
            variants.insert(String(cleaned.dropLast()))
        }

        if cleaned.hasSuffix("ing"), cleaned.count > 5 {
            let dropped = String(cleaned.dropLast(3))
            variants.insert(dropped)

            if hasDoubledTrailingLetter(dropped) {
                variants.insert(String(dropped.dropLast()))
            } else if dropped.hasSuffix("k") || dropped.hasSuffix("v") || dropped.hasSuffix("z") || dropped.hasSuffix("c") {
                variants.insert(dropped + "e")
            }
        }

        if cleaned.hasSuffix("ied"), cleaned.count > 4 {
            variants.insert(String(cleaned.dropLast(3)) + "y")
        } else if cleaned.hasSuffix("ed"), cleaned.count > 4 {
            let dropped = String(cleaned.dropLast(2))
            variants.insert(dropped)

            if dropped.count > 1, let last = dropped.last, dropped.dropLast().last == last {
                variants.insert(String(dropped.dropLast()))
            }

            let withSilentE = String(cleaned.dropLast())
            if withSilentE.hasSuffix("e") {
                variants.insert(withSilentE)
            }
        }

        if cleaned.hasSuffix("er"), cleaned.count > 4 {
            variants.insert(String(cleaned.dropLast(2)))
        }

        if cleaned.hasSuffix("est"), cleaned.count > 5 {
            variants.insert(String(cleaned.dropLast(3)))
        }

        return Set(variants.filter { $0.isEmpty == false })
    }

    private static func hasDoubledTrailingLetter(_ text: String) -> Bool {
        guard text.count >= 2 else {
            return false
        }

        let characters = Array(text)
        return characters[characters.count - 1] == characters[characters.count - 2]
    }
}

struct ReviewHistoryRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var reviewedAt: Date
    var reviewSessionID: UUID?
    var reviewSessionStartedAt: Date?
    var entryID: UUID?
    var term: String
    var meaning: String
    var mode: ReviewMode
    var decision: ReviewDecision
    var previousProficiency: ProficiencyLevel?
    var resultingProficiency: ProficiencyLevel?
    var sourceKinds: [ReviewSourceKind]
    var isHistoryOnly: Bool

    init(
        id: UUID = UUID(),
        reviewedAt: Date = .now,
        reviewSessionID: UUID? = nil,
        reviewSessionStartedAt: Date? = nil,
        entryID: UUID?,
        term: String,
        meaning: String,
        mode: ReviewMode,
        decision: ReviewDecision,
        previousProficiency: ProficiencyLevel?,
        resultingProficiency: ProficiencyLevel?,
        sourceKinds: [ReviewSourceKind],
        isHistoryOnly: Bool
    ) {
        self.id = id
        self.reviewedAt = reviewedAt
        self.reviewSessionID = reviewSessionID
        self.reviewSessionStartedAt = reviewSessionStartedAt
        self.entryID = entryID
        self.term = term
        self.meaning = meaning
        self.mode = mode
        self.decision = decision
        self.previousProficiency = previousProficiency
        self.resultingProficiency = resultingProficiency
        self.sourceKinds = sourceKinds
        self.isHistoryOnly = isHistoryOnly
    }
}
