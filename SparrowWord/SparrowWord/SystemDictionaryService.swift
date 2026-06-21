import CoreServices
import Foundation

struct LocalDictionaryEntry {
    var pronunciation: String
    var partOfSpeech: String?
    var chineseGlosses: [String]
    var collocations: [String]
}

nonisolated final class SystemDictionaryService {
    static let shared = SystemDictionaryService()

    private init() {}

    func entry(for term: String) -> LocalDictionaryEntry? {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return nil
        }

        let cfTerm = cleanedTerm as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cfTerm))

        guard let definition = DCSCopyTextDefinition(nil, cfTerm, range)?.takeRetainedValue() as String? else {
            return nil
        }

        let trimmedDefinition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDefinition.isEmpty else {
            return nil
        }

        let glossaryText = primaryGlossaryText(from: trimmedDefinition)

        return LocalDictionaryEntry(
            pronunciation: extractPronunciation(from: trimmedDefinition),
            partOfSpeech: extractPartOfSpeech(from: trimmedDefinition, term: cleanedTerm),
            chineseGlosses: extractChineseGlosses(from: glossaryText),
            collocations: extractCollocations(from: trimmedDefinition, term: cleanedTerm)
        )
    }

    private func primaryGlossaryText(from definition: String) -> String {
        let splitMarkers = ["▸", "PHRASAL VERBS"]

        for marker in splitMarkers {
            if let range = definition.range(of: marker) {
                return String(definition[..<range.lowerBound])
            }
        }

        return definition
    }

    private func extractPronunciation(from definition: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*[^|]+\|\s*([^|]+?)\s*\|"#, options: []) else {
            return ""
        }

        let nsRange = NSRange(definition.startIndex..<definition.endIndex, in: definition)
        guard let match = regex.firstMatch(in: definition, options: [], range: nsRange),
              let range = Range(match.range(at: 1), in: definition) else {
            return ""
        }

        return definition[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractPartOfSpeech(from definition: String, term: String) -> String? {
        if term.contains(" ") || term.contains("-") {
            return "短语"
        }

        let lowercased = definition.lowercased()

        if lowercased.contains("transitive verb") || lowercased.contains("intransitive verb") || lowercased.contains(" verb ") {
            return "动词"
        }

        if lowercased.contains(" noun ") || lowercased.contains(". noun") {
            return "名词"
        }

        if lowercased.contains(" adjective ") || lowercased.contains(". adjective") {
            return "形容词"
        }

        if lowercased.contains(" adverb ") || lowercased.contains(". adverb") {
            return "副词"
        }

        if lowercased.contains(" pronoun ") {
            return "代词"
        }

        if lowercased.contains(" preposition ") {
            return "介词"
        }

        return nil
    }

    private func extractChineseGlosses(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{Han}]{2,}(?:…?[\p{Han}]{1,})*"#, options: []) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let stopWords: Set<String> = ["他们", "她们", "我们", "你们", "我的", "你的", "这个", "那个", "一种", "一个"]

        let matches = regex.matches(in: text, options: [], range: nsRange).compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else {
                return nil
            }

            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2, !stopWords.contains(value) else {
                return nil
            }

            return value
        }

        return Array(matches.uniqued().prefix(4))
    }

    private func extractCollocations(from text: String, term: String) -> [String] {
        let escapedTerm = NSRegularExpression.escapedPattern(for: term.lowercased())
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b\#(escapedTerm)\b(?:\s+[a-z]+){1,2}"#, options: []) else {
            return []
        }

        let lowercased = text.lowercased()
        let nsRange = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
        let stopWords: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "for", "with", "from", "and", "or"]

        let phrases = regex.matches(in: lowercased, options: [], range: nsRange).compactMap { match -> String? in
            guard let range = Range(match.range, in: lowercased) else {
                return nil
            }

            let value = lowercased[range].trimmingCharacters(in: .whitespacesAndNewlines)
            let words = value.split(separator: " ").map(String.init)
            guard words.count >= 2 else {
                return nil
            }

            if let last = words.last, stopWords.contains(last) {
                return nil
            }

            return value
        }

        return Array(phrases.uniqued().prefix(5))
    }
}
