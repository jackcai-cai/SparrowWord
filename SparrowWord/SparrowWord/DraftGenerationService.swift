import Foundation

enum DraftFallbackKind: Equatable {
    case aiDisabled
    case missingAPIKey
    case requestFailed
}

enum DraftContentSource {
    case openAI(model: String)
    case localFallback(kind: DraftFallbackKind, reason: String?)
}

struct DraftGenerationResult {
    let content: GeneratedEntryContent
    let source: DraftContentSource
    let attemptedModel: String?

    var modelName: String? {
        switch source {
        case .openAI(let model):
            return model
        case .localFallback(let kind, _):
            return kind == .requestFailed ? attemptedModel : nil
        }
    }

    var fallbackKind: DraftFallbackKind? {
        guard case .localFallback(let kind, _) = source else {
            return nil
        }

        return kind
    }

    var fallbackReason: String? {
        guard case .localFallback(_, let reason) = source else {
            return nil
        }

        return reason
    }

    var failureReasonForMetadata: String? {
        guard fallbackKind == .requestFailed else {
            return nil
        }

        return fallbackReason
    }

    var fallbackDisplayReason: String? {
        switch source {
        case .openAI:
            return nil
        case .localFallback(let kind, let reason):
            switch kind {
            case .aiDisabled:
                return "AI 生成未启用"
            case .missingAPIKey:
                return "已启用 AI 生成，但未配置 API key"
            case .requestFailed:
                return reason
            }
        }
    }

}

final class DraftGenerationService {
    private let fallbackGenerator: LocalFallbackContentGenerator
    private let session: URLSession

    init(
        fallbackGenerator: LocalFallbackContentGenerator = LocalFallbackContentGenerator(),
        session: URLSession = .shared
    ) {
        self.fallbackGenerator = fallbackGenerator
        self.session = session
    }

    func fallbackDraft(term: String, sourceContext: String, kind: EntryKind, settings: AppSettings) -> GeneratedEntryContent {
        fallbackGenerator.generateFallback(term: term, sourceContext: sourceContext, kind: kind, settings: settings)
    }

    func generateDraft(term: String, sourceContext: String, kind: EntryKind, settings: AppSettings, apiKey: String) async -> DraftGenerationResult {
        let fallback = fallbackDraft(term: term, sourceContext: sourceContext, kind: kind, settings: settings)

        guard settings.isAIGenerationEnabled else {
            return DraftGenerationResult(
                content: fallback,
                source: .localFallback(kind: .aiDisabled, reason: "AI 生成未启用"),
                attemptedModel: nil
            )
        }

        guard !apiKey.isEmpty else {
            return DraftGenerationResult(
                content: fallback,
                source: .localFallback(kind: .missingAPIKey, reason: "已启用 AI 生成，但未配置 API key"),
                attemptedModel: nil
            )
        }

        let model = settings.resolvedOpenAIModel

        do {
            let remoteGenerator = OpenAIContentGenerator(apiKey: apiKey, model: model, session: session)
            let generated = try await remoteGenerator.generateContent(term: term, sourceContext: sourceContext, kind: kind, settings: settings)
            return DraftGenerationResult(
                content: normalizedContent(from: generated, fallback: fallback),
                source: .openAI(model: model),
                attemptedModel: model
            )
        } catch {
            return DraftGenerationResult(
                content: fallback,
                source: .localFallback(kind: .requestFailed, reason: compactReason(for: error)),
                attemptedModel: model
            )
        }
    }

    private func normalizedContent(from generated: GeneratedEntryContent, fallback: GeneratedEntryContent) -> GeneratedEntryContent {
        let normalizedMeaningGroups = MeaningGroup.normalized(
            generated.meaningGroups,
            fallbackPartOfSpeech: fallback.partOfSpeech,
            fallbackMeanings: fallback.meaningChoices,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )

        return GeneratedEntryContent(
            partOfSpeech: MeaningGroup.primaryPartOfSpeech(
                from: normalizedMeaningGroups,
                fallback: normalizedPartOfSpeech(generated.partOfSpeech, fallback: fallback.partOfSpeech)
            ),
            meaningChoices: normalizedChoices(
                MeaningGroup.flattenedMeanings(from: normalizedMeaningGroups),
                fallback: fallback.meaningChoices,
                targetCount: EntryCandidateDefaults.meaningChoiceCount
            ),
            meaningGroups: normalizedMeaningGroups,
            exampleChoices: normalizedChoices(
                generated.exampleChoices,
                fallback: fallback.exampleChoices,
                targetCount: EntryCandidateDefaults.exampleChoiceCount
            )
        )
    }

    private func normalizedPartOfSpeech(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedChoices(_ values: [String], fallback: [String], targetCount: Int) -> [String] {
        let cleanedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let cleanedFallback = fallback
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let merged = Array((cleanedValues + cleanedFallback).uniqued().prefix(targetCount))

        if merged.count == targetCount {
            return merged
        }

        if cleanedFallback.count >= targetCount {
            return Array(cleanedFallback.prefix(targetCount))
        }

        return Array((merged + cleanedFallback).uniqued().prefix(targetCount))
    }

    private func compactReason(for error: Error) -> String {
        let message = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else {
            return "AI 请求失败"
        }

        if message.count <= 140 {
            return message
        }

        let index = message.index(message.startIndex, offsetBy: 140)
        return "\(message[..<index])..."
    }
}
