import Foundation

enum LookupFallbackKind: Equatable, Sendable {
    case aiDisabled
    case missingAPIKey
    case requestFailed
}

enum LookupResultSource: Sendable {
    case openAI(model: String)
    case localFallback(kind: LookupFallbackKind, reason: String?)
}

struct LookupGenerationResult: Sendable {
    let content: LookupContent
    let source: LookupResultSource
    let attemptedModel: String?
    let localSource: LookupContentSource?

    var modelName: String? {
        switch source {
        case .openAI(let model):
            return model
        case .localFallback(let kind, _):
            return kind == .requestFailed ? attemptedModel : nil
        }
    }
}

nonisolated final class LookupService {
    private let fallbackGenerator: LocalFallbackLookupGenerator
    private let session: URLSession

    init(
        fallbackGenerator: LocalFallbackLookupGenerator = LocalFallbackLookupGenerator(),
        session: URLSession = .shared
    ) {
        self.fallbackGenerator = fallbackGenerator
        self.session = session
    }

    func fallbackLookup(term: String, kind: EntryKind, settings: AppSettings) -> LocalLookupFallbackResult {
        fallbackGenerator.generateFallback(term: term, kind: kind, settings: settings)
    }

    func generateLookup(term: String, kind: EntryKind, settings: AppSettings, apiKey: String) async -> LookupGenerationResult {
        let fallback = fallbackLookup(term: term, kind: kind, settings: settings)

        guard settings.isAIGenerationEnabled else {
            return LookupGenerationResult(
                content: fallback.content,
                source: .localFallback(kind: .aiDisabled, reason: "AI 生成未启用"),
                attemptedModel: nil,
                localSource: fallback.source
            )
        }

        guard !apiKey.isEmpty else {
            return LookupGenerationResult(
                content: fallback.content,
                source: .localFallback(kind: .missingAPIKey, reason: "已启用 AI 生成，但未配置 API key"),
                attemptedModel: nil,
                localSource: fallback.source
            )
        }

        let model = settings.resolvedOpenAIModel

        do {
            let remoteGenerator = OpenAILookupGenerator(apiKey: apiKey, model: model, session: session)
            let generated = try await remoteGenerator.generateLookup(term: term, kind: kind)
            return LookupGenerationResult(
                content: normalizedLookupContent(generated, fallback: fallback.content),
                source: .openAI(model: model),
                attemptedModel: model,
                localSource: nil
            )
        } catch {
            return LookupGenerationResult(
                content: fallback.content,
                source: .localFallback(kind: .requestFailed, reason: compactReason(for: error)),
                attemptedModel: model,
                localSource: fallback.source
            )
        }
    }

    func resolveChineseLookupCandidate(
        chinese: String,
        preferredKind: EntryKind,
        settings: AppSettings,
        apiKey: String
    ) async -> ChineseLookupCandidateResolution? {
        await resolveChineseLookupCandidates(
            chinese: chinese,
            preferredKind: preferredKind,
            settings: settings,
            apiKey: apiKey
        ).first
    }

    func resolveChineseLookupCandidates(
        chinese: String,
        preferredKind: EntryKind,
        settings: AppSettings,
        apiKey: String
    ) async -> [ChineseLookupCandidateResolution] {
        guard settings.isAIGenerationEnabled else {
            return []
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            return []
        }

        let model = settings.resolvedOpenAIModel

        do {
            let resolver = OpenAIChineseLookupResolver(
                apiKey: trimmedAPIKey,
                model: model,
                session: session
            )
            return try await resolver.resolveCandidates(
                chinese: chinese,
                preferredKind: preferredKind
            )
        } catch {
            return []
        }
    }

    private func normalizedLookupContent(_ generated: LookupContent, fallback: LookupContent) -> LookupContent {
        let normalizedExamples = generated.examples
            .filter { !$0.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(EntryCandidateDefaults.exampleChoiceCount)

        let normalizedMeaningGroups = MeaningGroup.normalized(
            generated.meaningGroups,
            fallbackPartOfSpeech: fallback.partOfSpeech,
            fallbackMeanings: fallback.meanings,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )

        return LookupContent(
            kind: generated.kind,
            term: generated.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback.term : generated.term,
            pronunciation: generated.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
            partOfSpeech: MeaningGroup.primaryPartOfSpeech(from: normalizedMeaningGroups, fallback: fallback.partOfSpeech),
            meanings: normalizedStrings(
                MeaningGroup.flattenedMeanings(from: normalizedMeaningGroups),
                fallback: fallback.meanings,
                minimumCount: 2
            ),
            meaningGroups: normalizedMeaningGroups,
            examples: normalizedExamples.isEmpty ? fallback.examples : Array(normalizedExamples),
            collocations: normalizedStrings(generated.collocations, fallback: fallback.collocations, minimumCount: 0),
            englishDefinitions: normalizedStrings(generated.englishDefinitions, fallback: fallback.englishDefinitions, minimumCount: 0),
            englishSynonyms: normalizedStrings(generated.englishSynonyms, fallback: fallback.englishSynonyms, minimumCount: 0),
            inflectionLines: normalizedStrings(generated.inflectionLines, fallback: fallback.inflectionLines, minimumCount: 0),
            referenceTags: normalizedStrings(generated.referenceTags, fallback: fallback.referenceTags, minimumCount: 0),
            translationDirection: generated.translationDirection ?? fallback.translationDirection
        )
    }

    private func normalizedStrings(_ values: [String], fallback: [String], minimumCount: Int) -> [String] {
        let cleanedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let cleanedFallback = fallback
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var merged = Array((cleanedValues + cleanedFallback).uniqued())
        if minimumCount > 0, merged.count < minimumCount {
            merged.append(contentsOf: cleanedFallback)
            merged = Array(merged.uniqued())
        }
        return merged
    }

    private func compactReason(for error: Error) -> String {
        let message = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else {
            return "查词请求失败"
        }

        if message.count <= 140 {
            return message
        }

        let index = message.index(message.startIndex, offsetBy: 140)
        return "\(message[..<index])..."
    }
}

struct LocalLookupFallbackResult: Sendable {
    var content: LookupContent
    var source: LookupContentSource
}

struct ChineseLookupCandidateResolution: Sendable {
    let english: String
    let kind: EntryKind
    let modelName: String
}

struct LocalFallbackLookupGenerator {
    private let draftGenerator = LocalFallbackContentGenerator()
    private let offlineLexicon = OfflineLexiconService.shared

    nonisolated init() {}

    nonisolated
    func generateFallback(term: String, kind: EntryKind, settings: AppSettings) -> LocalLookupFallbackResult {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = draftGenerator.generateFallback(term: cleanedTerm, sourceContext: "", kind: kind, settings: settings)
        let offlineLookup = offlineLexicon.lookupEnglish(term: cleanedTerm, kind: kind, manifest: settings.offlineResources)

        let examples: [LookupExample]
        if let offlineExamples = offlineLookup?.examples, !offlineExamples.isEmpty {
            examples = Array(offlineExamples.prefix(EntryCandidateDefaults.exampleChoiceCount))
        } else {
            examples = []
        }

        let content = LookupContent(
            kind: kind,
            term: cleanedTerm,
            pronunciation: offlineLookup?.pronunciation ?? "",
            partOfSpeech: offlineLookup?.partOfSpeech ?? draft.partOfSpeech,
            meanings: offlineLookup?.meanings.isEmpty == false ? (offlineLookup?.meanings ?? draft.meaningChoices) : draft.meaningChoices,
            meaningGroups: offlineLookup?.meaningGroups ?? draft.meaningGroups,
            examples: examples,
            collocations: offlineLookup?.collocations.isEmpty == false ? (offlineLookup?.collocations ?? fallbackCollocations(for: cleanedTerm, kind: kind)) : fallbackCollocations(for: cleanedTerm, kind: kind),
            englishDefinitions: offlineLookup?.englishDefinitions ?? [],
            englishSynonyms: offlineLookup?.englishSynonyms ?? [],
            inflectionLines: offlineLookup?.inflectionLines ?? [],
            referenceTags: offlineLookup?.referenceTags ?? [],
            translationDirection: nil
        )

        let sourceComponents = offlineLookup?.sourceComponents ?? [.fallback]
        let source = LookupContentSource(
            primary: sourceComponents.first ?? .fallback,
            components: Array(sourceComponents.dropFirst())
        )

        return LocalLookupFallbackResult(content: content, source: source)
    }

    nonisolated
    private func fallbackCollocations(for term: String, kind: EntryKind) -> [String] {
        guard !term.isEmpty else {
            return []
        }

        switch kind {
        case .word:
            return []
        case .phrase:
            return [term]
        case .sentence:
            return []
        }
    }
}

struct OpenAILookupGenerator {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    nonisolated
    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    nonisolated
    func generateLookup(term: String, kind: EntryKind) async throws -> LookupContent {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(term: term, kind: kind)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIContentGeneratorError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = decodeAPIErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIContentGeneratorError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let payload = try decoder.decode(LookupResponsesPayload.self, from: data)
        let structuredText = try payload.structuredOutputText()
        let structuredLookup = try decoder.decode(OpenAIStructuredLookup.self, from: Data(structuredText.utf8))

        return LookupContent(
            kind: kind,
            term: term,
            pronunciation: structuredLookup.pronunciation,
            partOfSpeech: structuredLookup.meaningGroups.first?.partOfSpeech ?? "",
            meanings: MeaningGroup.flattenedMeanings(from: structuredLookup.meaningGroups),
            meaningGroups: structuredLookup.meaningGroups,
            examples: structuredLookup.examples.map { LookupExample(english: $0.english, chinese: $0.chinese) },
            collocations: structuredLookup.collocations,
            translationDirection: nil
        )
    }

    nonisolated
    private func requestBody(term: String, kind: EntryKind) throws -> Data {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "pronunciation": [
                    "type": "string",
                    "description": "IPA pronunciation if available. Leave empty string only if uncertain.",
                    "maxLength": 30
                ],
                "meaningGroups": [
                    "type": "array",
                    "description": "One or more part-of-speech meaning groups.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "partOfSpeech": [
                                "type": "string",
                                "description": "One concise Simplified Chinese part-of-speech label.",
                                "minLength": 1,
                                "maxLength": 8
                            ],
                            "meanings": [
                                "type": "array",
                                "items": [
                                    "type": "string",
                                    "minLength": 1,
                                    "maxLength": 24
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
                "examples": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "english": [
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 100
                            ],
                            "chinese": [
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 60
                            ]
                        ],
                        "required": ["english", "chinese"],
                        "additionalProperties": false
                    ],
                    "minItems": 1,
                    "maxItems": 3
                ],
                "collocations": [
                    "type": "array",
                    "items": [
                        "type": "string",
                        "minLength": 1,
                        "maxLength": 40
                    ],
                    "minItems": 0,
                    "maxItems": 5
                ]
            ],
            "required": ["pronunciation", "meaningGroups", "examples", "collocations"],
            "additionalProperties": false
        ]

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "input": [
                [
                    "role": "developer",
                    "content": """
                    You create compact dictionary lookup results for a Chinese learner's macOS vocabulary app.
                    Return only JSON matching the schema.
                    Rules:
                    - The user primarily looks up English single words, but phrases are also allowed.
                    - meaningGroups: split senses by part of speech whenever the word has multiple common parts of speech.
                    - Each meaning group must have exactly 1 concise Simplified Chinese part-of-speech label.
                    - Within each group, meanings should be 1 to 4 mainstream Simplified Chinese dictionary-style senses, short and practical.
                    - Prefer grouping noun / verb / adjective senses separately instead of mixing them together.
                    - examples: 1 to 3 short natural English example sentences, each with a concise natural Simplified Chinese translation.
                    - collocations: 0 to 5 practical common collocations or short fixed phrases. Prefer usefulness over completeness.
                    - pronunciation: provide IPA when reasonably standard; if uncertain, use an empty string.
                    - If the item is a phrase, treat it as one unit and focus on its overall mainstream uses.
                    - No markdown, no numbering, no extra keys, no explanations.
                    """
                ],
                [
                    "role": "user",
                    "content": "kind: \(kind.title)\nterm: \(trimmedTerm)"
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "sparrow_word_lookup",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    nonisolated
    private func decodeAPIErrorMessage(from data: Data) -> String? {
        guard
            let payload = try? decoder.decode(LookupErrorPayload.self, from: data),
            let message = payload.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        else {
            return nil
        }

        return message
    }
}

private struct OpenAIChineseLookupResolver {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    nonisolated
    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    nonisolated
    func resolveCandidate(chinese: String, preferredKind: EntryKind) async throws -> ChineseLookupCandidateResolution {
        guard let candidate = try await resolveCandidates(
            chinese: chinese,
            preferredKind: preferredKind
        ).first else {
            throw OpenAIContentGeneratorError.emptyOutput
        }

        return candidate
    }

    nonisolated
    func resolveCandidates(chinese: String, preferredKind: EntryKind) async throws -> [ChineseLookupCandidateResolution] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(chinese: chinese, preferredKind: preferredKind)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIContentGeneratorError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = decodeAPIErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIContentGeneratorError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let payload = try decoder.decode(LookupResponsesPayload.self, from: data)
        let structuredText = try payload.structuredOutputText()
        let structuredCandidates = try decoder.decode(OpenAIChineseLookupCandidatesPayload.self, from: Data(structuredText.utf8))
        let candidates = structuredCandidates.candidates.compactMap { candidate -> ChineseLookupCandidateResolution? in
            let english = candidate.english.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty else {
                return nil
            }

            return ChineseLookupCandidateResolution(
                english: english,
                kind: candidate.resolvedKind,
                modelName: model
            )
        }

        guard !candidates.isEmpty else {
            throw OpenAIContentGeneratorError.emptyOutput
        }

        var merged: [ChineseLookupCandidateResolution] = []
        var seenKeys = Set<String>()

        for candidate in candidates {
            let key = "\(candidate.kind.rawValue)::\(candidate.english.lowercased())"
            guard seenKeys.insert(key).inserted else {
                continue
            }

            merged.append(candidate)

            if merged.count >= 6 {
                break
            }
        }

        return merged
    }

    nonisolated
    private func requestBody(chinese: String, preferredKind: EntryKind) throws -> Data {
        let trimmedChinese = chinese.trimmingCharacters(in: .whitespacesAndNewlines)

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "candidates": [
                    "type": "array",
                    "description": "One to six ranked English translation candidates for dictionary lookup.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "english": [
                                "type": "string",
                                "description": "One concise mainstream English translation candidate for dictionary lookup.",
                                "minLength": 1,
                                "maxLength": 80
                            ],
                            "kind": [
                                "type": "string",
                                "enum": ["word", "phrase"],
                                "description": "Whether the English candidate is best treated as a single word or a phrase."
                            ]
                        ],
                        "required": ["english", "kind"],
                        "additionalProperties": false
                    ],
                    "minItems": 1,
                    "maxItems": 6
                ]
            ],
            "required": ["candidates"],
            "additionalProperties": false
        ]

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "input": [
                [
                    "role": "developer",
                    "content": """
                    You resolve a Chinese word or phrase into one or more concise English dictionary lookup candidates for a vocabulary app.
                    Return only JSON matching the schema.
                    Rules:
                    - Return 1 to 6 ranked candidates, most likely first.
                    - Include multiple alternatives when the Chinese query has multiple common English renderings.
                    - Prefer dictionary-style vocabulary items or fixed phrases, not full sentence translations.
                    - If the Chinese input is a phrase, preserve it as one English unit when possible.
                    - Avoid explanations, notes, punctuation lists, or multiple options joined into one field.
                    - If the input is ambiguous, include the most common everyday meanings first.
                    """
                ],
                [
                    "role": "user",
                    "content": """
                    preferred_kind: \(preferredKind.title)
                    chinese: \(trimmedChinese)
                    """
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "sparrow_word_chinese_lookup_candidate",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    nonisolated
    private func decodeAPIErrorMessage(from data: Data) -> String? {
        guard
            let payload = try? decoder.decode(LookupErrorPayload.self, from: data),
            let message = payload.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        else {
            return nil
        }

        return message
    }
}

private struct OpenAIStructuredLookup: Decodable {
    struct MeaningGroupPayload: Decodable {
        let partOfSpeech: String
        let meanings: [String]
    }

    struct Example: Decodable {
        let english: String
        let chinese: String
    }

    let pronunciation: String
    let meaningGroups: [MeaningGroup]
    let examples: [Example]
    let collocations: [String]

    enum CodingKeys: String, CodingKey {
        case pronunciation
        case meaningGroups
        case examples
        case collocations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        let payloads = try container.decode([MeaningGroupPayload].self, forKey: .meaningGroups)
        meaningGroups = MeaningGroup.normalized(
            payloads.map { MeaningGroup(partOfSpeech: $0.partOfSpeech, meanings: $0.meanings) },
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        examples = try container.decodeIfPresent([Example].self, forKey: .examples) ?? []
        collocations = try container.decodeIfPresent([String].self, forKey: .collocations) ?? []
    }
}

private struct OpenAIChineseLookupCandidate: Decodable {
    let english: String
    let kind: String

    var resolvedKind: EntryKind {
        kind == "phrase" ? .phrase : .word
    }
}

private struct OpenAIChineseLookupCandidatesPayload: Decodable {
    let candidates: [OpenAIChineseLookupCandidate]
}

private struct LookupResponsesPayload: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    func structuredOutputText() throws -> String {
        if let outputText, !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.content)
            .flatMap { $0 }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let text, !text.isEmpty {
            return text
        }

        let refusal = output?
            .compactMap(\.content)
            .flatMap { $0 }
            .compactMap(\.refusal)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        if let refusal {
            throw OpenAIContentGeneratorError.modelRefused(refusal)
        }

        throw OpenAIContentGeneratorError.emptyOutput
    }

    struct OutputItem: Decodable {
        let content: [OutputContent]?
    }

    struct OutputContent: Decodable {
        let text: String?
        let refusal: String?
    }
}

private struct LookupErrorPayload: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String?
    }
}
