import Foundation

protocol AIContentGenerator {
    func generateContent(term: String, sourceContext: String, kind: EntryKind, settings: AppSettings) async throws -> GeneratedEntryContent
}

struct LocalFallbackContentGenerator: AIContentGenerator {
    private let offlineLexicon = OfflineLexiconService.shared
    private let dictionaryService = SystemDictionaryService.shared

    func generateContent(term: String, sourceContext: String, kind: EntryKind, settings: AppSettings) async throws -> GeneratedEntryContent {
        generateFallback(term: term, sourceContext: sourceContext, kind: kind, settings: settings)
    }

    func generateFallback(term: String, sourceContext: String, kind: EntryKind, settings: AppSettings) -> GeneratedEntryContent {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedContext = sourceContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPhrase = kind == .phrase || cleanedTerm.contains(" ") || cleanedTerm.contains("-")
        let dictionaryEntry = dictionaryService.entry(for: cleanedTerm)
        let offlineLookup = offlineLexicon.lookupEnglish(term: cleanedTerm, kind: kind, manifest: settings.offlineResources)
        let meaningGroups = meaningGroups(
            for: cleanedTerm,
            kind: kind,
            isPhrase: isPhrase,
            dictionaryEntry: dictionaryEntry,
            offlineLookup: offlineLookup
        )

        return GeneratedEntryContent(
            partOfSpeech: MeaningGroup.primaryPartOfSpeech(
                from: meaningGroups,
                fallback: partOfSpeech(
                    for: cleanedTerm,
                    kind: kind,
                    isPhrase: isPhrase,
                    dictionaryEntry: dictionaryEntry,
                    offlineLookup: offlineLookup
                )
            ),
            meaningChoices: meaningChoices(
                for: cleanedTerm,
                sourceContext: cleanedContext,
                isPhrase: isPhrase,
                dictionaryEntry: dictionaryEntry,
                offlineLookup: offlineLookup,
                meaningGroups: meaningGroups
            ),
            meaningGroups: meaningGroups,
            exampleChoices: exampleChoices(for: cleanedTerm, sourceContext: cleanedContext, offlineLookup: offlineLookup)
        )
    }

    private func partOfSpeech(for term: String, kind: EntryKind, isPhrase: Bool, dictionaryEntry: LocalDictionaryEntry?, offlineLookup: OfflineLexiconLookup?) -> String {
        if let offlinePartOfSpeech = offlineLookup?.partOfSpeech, !offlinePartOfSpeech.isEmpty {
            return offlinePartOfSpeech
        }

        if kind == .sentence {
            return "句子"
        }

        if let dictionaryPartOfSpeech = dictionaryEntry?.partOfSpeech, !dictionaryPartOfSpeech.isEmpty {
            return dictionaryPartOfSpeech
        }

        guard !term.isEmpty else {
            return "词语"
        }

        if isPhrase {
            return "短语"
        }

        let lowercased = term.lowercased()

        if lowercased.hasSuffix("ly") {
            return "副词"
        }

        if lowercased.hasSuffix("ing") || lowercased.hasSuffix("ed") {
            return "动词"
        }

        if lowercased.hasSuffix("ous") || lowercased.hasSuffix("ful") || lowercased.hasSuffix("ive") {
            return "形容词"
        }

        return "单词"
    }

    private func meaningGroups(
        for term: String,
        kind: EntryKind,
        isPhrase: Bool,
        dictionaryEntry: LocalDictionaryEntry?,
        offlineLookup: OfflineLexiconLookup?
    ) -> [MeaningGroup] {
        if let offlineMeaningGroups = offlineLookup?.meaningGroups, !offlineMeaningGroups.isEmpty {
            return MeaningGroup.normalized(
                offlineMeaningGroups,
                fallbackPartOfSpeech: partOfSpeech(
                    for: term,
                    kind: kind,
                    isPhrase: isPhrase,
                    dictionaryEntry: dictionaryEntry,
                    offlineLookup: offlineLookup
                ),
                fallbackMeanings: offlineLookup?.meanings ?? [],
                maxMeanings: EntryCandidateDefaults.meaningChoiceCount
            )
        }

        let dictionaryMeanings = dictionaryEntry?.chineseGlosses ?? []
        guard !dictionaryMeanings.isEmpty else {
            return []
        }

        return MeaningGroup.normalized(
            [
                MeaningGroup(
                    partOfSpeech: partOfSpeech(
                        for: term,
                        kind: kind,
                        isPhrase: isPhrase,
                        dictionaryEntry: dictionaryEntry,
                        offlineLookup: offlineLookup
                    ),
                    meanings: dictionaryMeanings
                )
            ],
            fallbackPartOfSpeech: partOfSpeech(
                for: term,
                kind: kind,
                isPhrase: isPhrase,
                dictionaryEntry: dictionaryEntry,
                offlineLookup: offlineLookup
            ),
            fallbackMeanings: dictionaryMeanings,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
    }

    private func meaningChoices(
        for term: String,
        sourceContext: String,
        isPhrase: Bool,
        dictionaryEntry: LocalDictionaryEntry?,
        offlineLookup: OfflineLexiconLookup?,
        meaningGroups: [MeaningGroup]
    ) -> [String] {
        let groupedMeanings = MeaningGroup.flattenedMeanings(
            from: meaningGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        if !groupedMeanings.isEmpty {
            return groupedMeanings
        }

        let offlineMeanings = offlineLookup?.meanings ?? []
        let dictionaryMeanings = dictionaryEntry?.chineseGlosses ?? []
        let mergedDictionaryMeanings = Array((offlineMeanings + dictionaryMeanings).uniqued())

        if !mergedDictionaryMeanings.isEmpty {
            return Array(mergedDictionaryMeanings.prefix(EntryCandidateDefaults.meaningChoiceCount))
        }
        return []
    }

    private func exampleChoices(for _: String, sourceContext: String, offlineLookup: OfflineLexiconLookup?) -> [String] {
        if let offlineExamples = offlineLookup?.examples.map(\.english), !offlineExamples.isEmpty {
            return Array(offlineExamples.prefix(EntryCandidateDefaults.exampleChoiceCount))
        }

        guard !sourceContext.isEmpty else {
            return []
        }

        return Array([sourceContext].uniqued().prefix(EntryCandidateDefaults.exampleChoiceCount))
    }
}

struct OpenAIContentGenerator: AIContentGenerator {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func generateContent(term: String, sourceContext: String, kind: EntryKind, settings: AppSettings) async throws -> GeneratedEntryContent {
        let client = OpenAIResponsesClient(apiKey: apiKey, session: session)
        let structuredText = try await client.requestStructuredOutput(
            body: try requestBody(term: term, sourceContext: sourceContext, kind: kind)
        )
        let structuredDraft = try decoder.decode(OpenAIStructuredDraft.self, from: Data(structuredText.utf8))

        return GeneratedEntryContent(
            partOfSpeech: structuredDraft.meaningGroups.first?.partOfSpeech ?? "",
            meaningChoices: MeaningGroup.flattenedMeanings(from: structuredDraft.meaningGroups),
            meaningGroups: structuredDraft.meaningGroups,
            exampleChoices: structuredDraft.exampleChoices
        )
    }

    private func requestBody(term: String, sourceContext: String, kind: EntryKind) throws -> Data {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = sourceContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrompt: String

        if trimmedContext.isEmpty {
            userPrompt = "kind: \(kind.title)\nterm: \(trimmedTerm)"
        } else {
            userPrompt = """
            kind: \(kind.title)
            term: \(trimmedTerm)
            source_context: \(trimmedContext)
            """
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "meaningGroups": [
                    "type": "array",
                    "description": "One or more part-of-speech meaning groups.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "partOfSpeech": [
                                "type": "string",
                                "description": "One concise Simplified Chinese part-of-speech label such as 名词, 动词, 形容词, 副词, 短语.",
                                "minLength": 1,
                                "maxLength": 8
                            ],
                            "meanings": [
                                "type": "array",
                                "description": "One to four brief mainstream Simplified Chinese dictionary-style senses for this part of speech.",
                                "items": [
                                    "type": "string",
                                    "minLength": 1,
                                    "maxLength": 20
                                ],
                                "minItems": 1,
                                "maxItems": 4
                            ]
                        ],
                        "required": ["partOfSpeech", "meanings"],
                        "additionalProperties": false
                    ],
                    "minItems": 1,
                    "maxItems": 3
                ],
                "exampleChoices": [
                    "type": "array",
                    "description": "One to three short natural everyday English example sentences using the term directly.",
                    "items": [
                        "type": "string",
                        "minLength": 1,
                        "maxLength": 90
                    ],
                    "minItems": 1,
                    "maxItems": 3
                ]
            ],
            "required": ["meaningGroups", "exampleChoices"],
            "additionalProperties": false
        ]

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "input": [
                [
                    "role": "developer",
                    "content": """
                    You create compact dictionary-style draft content for a macOS vocabulary app for Chinese learners.
                    Return only JSON that matches the provided schema.
                    Rules:
                    - meaningGroups: split senses by part of speech whenever the word has multiple common parts of speech.
                    - Each group must have exactly 1 concise Simplified Chinese part-of-speech label.
                    - Each group's meanings should be brief mainstream dictionary-style senses, not full explanations or teaching notes.
                    - Prefer separating noun / verb / adjective uses instead of mixing them together.
                    - exampleChoices: 1 to 3 short natural English example sentences.
                    - Keep examples everyday and direct, not literary or overly formal.
                    - If the term is a phrase, treat it as one unit and give overall mainstream uses.
                    - Do not explain individual words inside a phrase.
                    - If source context is provided, use it only to disambiguate toward the most likely common sense.
                    - No numbering, quotes, markdown, labels, or extra keys.
                    """
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "word_dock_entry_draft",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

}

private struct OpenAIStructuredDraft: Decodable {
    let meaningGroups: [MeaningGroup]
    let exampleChoices: [String]

    enum CodingKeys: String, CodingKey {
        case meaningGroups
        case exampleChoices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meaningGroups = MeaningGroup.normalized(
            try container.decode([MeaningGroup].self, forKey: .meaningGroups),
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        exampleChoices = try container.decodeIfPresent([String].self, forKey: .exampleChoices) ?? []
    }
}

enum OpenAIContentGeneratorError: LocalizedError {
    case invalidResponse
    case emptyOutput
    case modelRefused(String)
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI 返回了无法识别的响应。"
        case .emptyOutput:
            return "OpenAI 没有返回可解析的结构化内容。"
        case .modelRefused(let reason):
            return "OpenAI 拒绝了这次请求：\(reason)"
        case .requestFailed(let statusCode, let message):
            return "OpenAI 请求失败（\(statusCode)）：\(message)"
        }
    }
}
