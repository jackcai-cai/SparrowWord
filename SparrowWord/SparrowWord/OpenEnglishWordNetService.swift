import Foundation
import SQLite3

struct OpenEnglishWordNetLookup: Sendable {
    var pronunciation: String
    var englishDefinitions: [String]
    var englishSynonyms: [String]
    var inflectionLines: [String]
}

private struct OpenEnglishWordNetDefinitionPayload: Sendable {
    var definitions: [String]
    var synonyms: [String]
}

nonisolated final class OpenEnglishWordNetService {
    static let shared = OpenEnglishWordNetService()

    private let fileManager = FileManager.default

    private init() {}

    func lookup(term: String, kind: EntryKind, manifest: OfflineResourceManifest) -> OpenEnglishWordNetLookup? {
        guard kind != .sentence else {
            return nil
        }

        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return nil
        }

        let dbURL = databaseURL(for: manifest)
        guard fileManager.fileExists(atPath: dbURL.path),
              let database = try? SQLiteDatabase(
                url: dbURL,
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
              ) else {
            return nil
        }

        let entries = lookupEntries(term: cleanedTerm, kind: kind, database: database)
        guard !entries.isEmpty else {
            return nil
        }

        let synsets = lookupSynsets(
            ids: entries.flatMap(\.synsetIDs),
            database: database
        )

        let pronunciation = preferredPronunciation(from: entries)
        let definitionPayload = resolvedEnglishDefinitionPayload(
            entries: entries,
            synsets: synsets
        )
        let inflectionLines = resolvedInflectionLines(
            entries: entries,
            query: cleanedTerm
        )

        guard !pronunciation.isEmpty
            || !definitionPayload.definitions.isEmpty
            || !definitionPayload.synonyms.isEmpty
            || !inflectionLines.isEmpty else {
            return nil
        }

        return OpenEnglishWordNetLookup(
            pronunciation: pronunciation,
            englishDefinitions: definitionPayload.definitions,
            englishSynonyms: definitionPayload.synonyms,
            inflectionLines: inflectionLines
        )
    }

    func hasLookupHit(term: String, kind: EntryKind, manifest: OfflineResourceManifest) -> Bool {
        lookup(term: term, kind: kind, manifest: manifest) != nil
    }

    func suggestions(
        term: String,
        kind: EntryKind,
        manifest: OfflineResourceManifest,
        limit: Int = 8
    ) -> [LookupSuggestion] {
        guard kind != .sentence else {
            return []
        }

        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedTerm.count >= 2 else {
            return []
        }

        let dbURL = databaseURL(for: manifest)
        guard fileManager.fileExists(atPath: dbURL.path),
              let database = try? SQLiteDatabase(
                url: dbURL,
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
              ) else {
            return []
        }

        let expandedLimit = max(limit * 3, 18)
        var suggestions: [LookupSuggestion] = []

        if kind == .word {
            for candidate in Array(normalizedLookupCandidates(for: cleanedTerm, kind: kind).dropFirst()) {
                suggestions.append(
                    contentsOf: lookupSuggestionsForLemmas(
                        lemmas(forForm: candidate, database: database),
                        originalTerm: cleanedTerm,
                        fallbackKind: kind,
                        reason: .inflection,
                        database: database
                    )
                )
            }
        }

        suggestions.append(
            contentsOf: lookupSuggestionsForEntries(
                prefixEntries(prefix: cleanedTerm, database: database, limit: expandedLimit),
                originalTerm: cleanedTerm,
                fallbackKind: kind,
                reason: .prefix,
                database: database
            )
        )

        return Array(deduplicatedSuggestions(suggestions).prefix(limit))
    }

    private struct EntryRow: Sendable {
        var lemma: String
        var partOfSpeech: String
        var pronunciations: [String]
        var forms: [String]
        var synsetIDs: [String]
    }

    private struct SynsetRow: Sendable {
        var id: String
        var partOfSpeech: String
        var definitions: [String]
        var members: [String]
    }

    private func databaseURL(for manifest: OfflineResourceManifest) -> URL {
        if !manifest.resourcesDirectoryPath.isEmpty {
            return URL(fileURLWithPath: manifest.resourcesDirectoryPath)
                .appendingPathComponent("oewn", isDirectory: true)
                .appendingPathComponent("oewn.sqlite")
        }

        if !manifest.ecdictDatabasePath.isEmpty {
            return URL(fileURLWithPath: manifest.ecdictDatabasePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("oewn", isDirectory: true)
                .appendingPathComponent("oewn.sqlite")
        }

        return StorageService()
            .offlineResourcesDirectory()
            .appendingPathComponent("oewn", isDirectory: true)
            .appendingPathComponent("oewn.sqlite")
    }

    private func lookupEntries(term: String, kind: EntryKind, database: SQLiteDatabase) -> [EntryRow] {
        let candidates = normalizedLookupCandidates(for: term, kind: kind)
        guard !candidates.isEmpty else {
            return []
        }

        for candidate in candidates {
            let exactEntries = entryRows(forLemma: candidate, database: database)
            if !exactEntries.isEmpty {
                return exactEntries
            }
        }

        var inferredEntries: [EntryRow] = []
        for candidate in candidates {
            let lemmas = lemmas(forForm: candidate, database: database)
            for lemma in lemmas {
                inferredEntries.append(contentsOf: entryRows(forLemma: lemma, database: database))
            }
        }

        return deduplicatedEntries(inferredEntries)
    }

    private func entryRows(forLemma lemma: String, database: SQLiteDatabase) -> [EntryRow] {
        do {
            let statement = try database.prepare(
                """
                SELECT lemma, part_of_speech, pronunciations_json, forms_json, synsets_json
                FROM oewn_entries
                WHERE lower(lemma) = lower(?)
                ORDER BY lemma ASC;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, lemma, -1, SQLITE_TRANSIENT)

            var rows: [EntryRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(
                    EntryRow(
                        lemma: sqliteString(statement, column: 0),
                        partOfSpeech: sqliteString(statement, column: 1),
                        pronunciations: decodeJSONArrayString(sqliteString(statement, column: 2)),
                        forms: decodeJSONArrayString(sqliteString(statement, column: 3)),
                        synsetIDs: decodeJSONArrayString(sqliteString(statement, column: 4))
                    )
                )
            }

            return rows
        } catch {
            return []
        }
    }

    private func lemmas(forForm form: String, database: SQLiteDatabase) -> [String] {
        do {
            let statement = try database.prepare(
                """
                SELECT lemma
                FROM oewn_forms
                WHERE lower(form) = lower(?)
                ORDER BY lemma ASC
                LIMIT 8;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, form, -1, SQLITE_TRANSIENT)

            var lemmas: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                lemmas.append(sqliteString(statement, column: 0))
            }

            return lemmas.uniqued()
        } catch {
            return []
        }
    }

    private func lookupSynsets(ids: [String], database: SQLiteDatabase) -> [String: SynsetRow] {
        let uniqueIDs = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        guard !uniqueIDs.isEmpty else {
            return [:]
        }

        do {
            let placeholders = Array(repeating: "?", count: uniqueIDs.count).joined(separator: ",")
            let statement = try database.prepare(
                """
                SELECT synset_id, part_of_speech, definitions_json, members_json
                FROM oewn_synsets
                WHERE synset_id IN (\(placeholders));
                """
            )
            defer { sqlite3_finalize(statement) }

            for (index, id) in uniqueIDs.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), id, -1, SQLITE_TRANSIENT)
            }

            var result: [String: SynsetRow] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let row = SynsetRow(
                    id: sqliteString(statement, column: 0),
                    partOfSpeech: sqliteString(statement, column: 1),
                    definitions: decodeJSONArrayString(sqliteString(statement, column: 2)),
                    members: decodeJSONArrayString(sqliteString(statement, column: 3))
                )
                result[row.id] = row
            }

            return result
        } catch {
            return [:]
        }
    }

    private func prefixEntries(prefix: String, database: SQLiteDatabase, limit: Int) -> [EntryRow] {
        do {
            let statement = try database.prepare(
                """
                SELECT lemma, part_of_speech, pronunciations_json, forms_json, synsets_json
                FROM oewn_entries
                WHERE lemma LIKE ? COLLATE NOCASE
                ORDER BY
                    CASE
                        WHEN lower(lemma) = lower(?) THEN 0
                        WHEN lower(lemma) LIKE lower(?) || ' %' THEN 1
                        WHEN lower(lemma) LIKE lower(?) || '-%' THEN 1
                        ELSE 2
                    END,
                    length(lemma) ASC,
                    lemma ASC
                LIMIT ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, "\(prefix)%", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, prefix, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, prefix, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, prefix, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 5, Int32(limit))

            var rows: [EntryRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(
                    EntryRow(
                        lemma: sqliteString(statement, column: 0),
                        partOfSpeech: sqliteString(statement, column: 1),
                        pronunciations: decodeJSONArrayString(sqliteString(statement, column: 2)),
                        forms: decodeJSONArrayString(sqliteString(statement, column: 3)),
                        synsetIDs: decodeJSONArrayString(sqliteString(statement, column: 4))
                    )
                )
            }

            return rows
        } catch {
            return []
        }
    }

    private func preferredPronunciation(from entries: [EntryRow]) -> String {
        let pronunciations = entries
            .flatMap(\.pronunciations)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        return pronunciations.joined(separator: ", ")
    }

    private func lookupSuggestionsForLemmas(
        _ lemmas: [String],
        originalTerm: String,
        fallbackKind: EntryKind,
        reason: LookupSuggestionReason,
        database: SQLiteDatabase
    ) -> [LookupSuggestion] {
        lookupSuggestionsForEntries(
            lemmas.flatMap { entryRows(forLemma: $0, database: database) },
            originalTerm: originalTerm,
            fallbackKind: fallbackKind,
            reason: reason,
            database: database
        )
    }

    private func lookupSuggestionsForEntries(
        _ entries: [EntryRow],
        originalTerm: String,
        fallbackKind: EntryKind,
        reason: LookupSuggestionReason,
        database: SQLiteDatabase
    ) -> [LookupSuggestion] {
        let distinctEntries = deduplicatedEntries(entries)
        guard !distinctEntries.isEmpty else {
            return []
        }

        let synsets = lookupSynsets(
            ids: distinctEntries.flatMap(\.synsetIDs),
            database: database
        )

        return distinctEntries.compactMap { entry in
            let cleanedLemma = entry.lemma.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedLemma.isEmpty,
                  cleanedLemma.caseInsensitiveCompare(originalTerm) != .orderedSame else {
                return nil
            }

            let isPhrase = cleanedLemma.contains(" ") || cleanedLemma.contains("-")
            return LookupSuggestion(
                term: cleanedLemma,
                preview: previewText(for: entry, synsets: synsets),
                reason: isPhrase ? .phraseExpansion : reason,
                kind: isPhrase ? .phrase : fallbackKind
            )
        }
    }

    private func previewText(for entry: EntryRow, synsets: [String: SynsetRow]) -> String {
        var previews: [String] = []

        for synsetID in entry.synsetIDs.prefix(2) {
            guard let synset = synsets[synsetID] else {
                continue
            }

            for definition in synset.definitions {
                let cleaned = definition.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else {
                    continue
                }

                previews.append(cleaned)
                if previews.count >= 2 {
                    break
                }
            }

            if previews.count >= 2 {
                break
            }
        }

        if previews.isEmpty {
            let synonyms = entry.synsetIDs
                .compactMap { synsets[$0] }
                .flatMap(\.members)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare(entry.lemma) != .orderedSame }
                .uniqued()
            if !synonyms.isEmpty {
                previews.append("Synonyms: \(synonyms.prefix(3).joined(separator: ", "))")
            }
        }

        return previews.prefix(2).joined(separator: " · ")
    }

    private func resolvedEnglishDefinitionPayload(
        entries: [EntryRow],
        synsets: [String: SynsetRow]
    ) -> OpenEnglishWordNetDefinitionPayload {
        let distinctPartsOfSpeech = Set(entries.map(\.partOfSpeech))

        var definitions: [String] = []
        var synonyms: [String] = []
        for entry in entries {
            let partOfSpeechLabel = englishPartOfSpeechLabel(entry.partOfSpeech)

            for synsetID in entry.synsetIDs.prefix(6) {
                guard let synset = synsets[synsetID] else {
                    continue
                }

                for definition in synset.definitions {
                    let cleaned = definition.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else {
                        continue
                    }

                    if distinctPartsOfSpeech.count > 1 {
                        definitions.append("\(partOfSpeechLabel): \(cleaned)")
                    } else {
                        definitions.append(cleaned)
                    }
                }

                let synsetSynonyms = synset.members
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.caseInsensitiveCompare(entry.lemma) != .orderedSame }
                    .uniqued()
                if !synsetSynonyms.isEmpty {
                    appendUniqueTerms(from: synsetSynonyms, into: &synonyms)
                }
            }
        }

        return OpenEnglishWordNetDefinitionPayload(
            definitions: Array(definitions.uniqued().prefix(6)),
            synonyms: Array(synonyms.prefix(8))
        )
    }

    private func appendUniqueTerms(from terms: [String], into target: inout [String]) {
        for term in terms {
            if target.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) == false {
                target.append(term)
            }
        }
    }

    private func resolvedInflectionLines(entries: [EntryRow], query: String) -> [String] {
        var lines: [String] = []

        for entry in entries {
            if entry.lemma.caseInsensitiveCompare(query) != .orderedSame {
                lines.append("原形：\(entry.lemma)")
            }

            let forms = entry.forms
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare(query) != .orderedSame }
                .uniqued()

            guard !forms.isEmpty else {
                continue
            }

            switch entry.partOfSpeech {
            case "a", "s":
                if forms.indices.contains(0) {
                    lines.append("比较级：\(forms[0])")
                }
                if forms.indices.contains(1) {
                    lines.append("最高级：\(forms[1])")
                }
                if forms.count > 2 {
                    lines.append("其他词形：\(forms.dropFirst(2).prefix(3).joined(separator: ", "))")
                }
            default:
                lines.append("其他词形：\(forms.prefix(4).joined(separator: ", "))")
            }
        }

        return Array(lines.uniqued().prefix(5))
    }

    private func englishPartOfSpeechLabel(_ code: String) -> String {
        switch code {
        case "n":
            return "Noun"
        case "v":
            return "Verb"
        case "a", "s":
            return "Adjective"
        case "r":
            return "Adverb"
        default:
            return "Sense"
        }
    }

    private func normalizedLookupCandidates(for term: String, kind: EntryKind) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var candidates = [trimmed]
        let normalizedSpacing = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if normalizedSpacing != trimmed {
            candidates.append(normalizedSpacing)
        }

        let normalizedHyphen = normalizedSpacing
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
        if normalizedHyphen != normalizedSpacing {
            candidates.append(normalizedHyphen)
        }

        if kind == .phrase || normalizedHyphen.contains(" ") || normalizedHyphen.contains("-") {
            candidates.append(normalizedHyphen.replacingOccurrences(of: "-", with: " "))
            candidates.append(normalizedHyphen.replacingOccurrences(of: " ", with: "-"))
        }

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func decodeJSONArrayString(_ rawValue: String) -> [String] {
        guard let data = rawValue.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func deduplicatedEntries(_ entries: [EntryRow]) -> [EntryRow] {
        var seen: Set<String> = []
        return entries.filter { entry in
            let key = "\(entry.lemma.lowercased())::\(entry.partOfSpeech)"
            return seen.insert(key).inserted
        }
    }

    private func deduplicatedSuggestions(_ suggestions: [LookupSuggestion]) -> [LookupSuggestion] {
        var seen: Set<String> = []
        return suggestions.filter { suggestion in
            let key = "\(suggestion.kind.rawValue)::\(suggestion.term.lowercased())"
            return seen.insert(key).inserted
        }
    }

    private func sqliteString(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, column) else {
            return ""
        }

        return String(cString: cString)
    }
}
