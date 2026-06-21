import Foundation
import SQLite3

struct OfflineLexiconLookup {
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
    var sourceComponents: [LookupSourceComponentKind]
}

struct OfflineLexiconCore: Sendable {
    var pronunciation: String
    var partOfSpeech: String
    var meanings: [String]
    var meaningGroups: [MeaningGroup]
    var collocations: [String]
    var englishDefinitions: [String]
    var englishSynonyms: [String]
    var inflectionLines: [String]
    var referenceTags: [String]
    var sourceComponents: [LookupSourceComponentKind]
}

private struct ECDICTRow: Sendable {
    var word: String
    var phonetic: String
    var pos: String
    var translation: String
    var definition: String
    var exchange: String
    var collins: Int?
    var oxford: Int?
    var tag: String
    var bnc: Int?
    var frq: Int?
    var audio: String
}

nonisolated final class OfflineLexiconService {
    static let shared = OfflineLexiconService()

    private init() {}

    func lookupEnglish(term: String, kind: EntryKind, manifest: OfflineResourceManifest) -> OfflineLexiconLookup? {
        let resolvedKind = effectiveLookupKind(for: term, requestedKind: kind)

        guard let core = lookupEnglishCore(term: term, kind: resolvedKind, manifest: manifest) else {
            let examples = lookupEnglishExamples(term: term, manifest: manifest)
            guard !examples.isEmpty else {
                return nil
            }

            return OfflineLexiconLookup(
                pronunciation: "",
                partOfSpeech: resolvedKind == .phrase ? "短语" : "单词",
                meanings: [],
                meaningGroups: [],
                examples: examples,
                collocations: [],
                englishDefinitions: [],
                englishSynonyms: [],
                inflectionLines: [],
                referenceTags: [],
                sourceComponents: [.tatoeba]
            )
        }

        let examples = lookupEnglishExamples(term: term, manifest: manifest)
        let localizedCollocations = localizedCollocations(core.collocations, manifest: manifest)
        let sourceComponents = examples.isEmpty
            ? core.sourceComponents
            : Array((core.sourceComponents + [.tatoeba]).uniqued())

        return OfflineLexiconLookup(
            pronunciation: core.pronunciation,
            partOfSpeech: core.partOfSpeech,
            meanings: core.meanings,
            meaningGroups: core.meaningGroups,
            examples: examples,
            collocations: localizedCollocations,
            englishDefinitions: core.englishDefinitions,
            englishSynonyms: core.englishSynonyms,
            inflectionLines: core.inflectionLines,
            referenceTags: core.referenceTags,
            sourceComponents: sourceComponents
        )
    }

    func lookupEnglishQuickPreview(term: String, kind: EntryKind, manifest: OfflineResourceManifest) -> OfflineLexiconCore? {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return nil
        }

        let resolvedKind = effectiveLookupKind(for: cleanedTerm, requestedKind: kind)
        let ecdictRow = firstECDICTMatch(for: cleanedTerm, kind: resolvedKind, manifest: manifest)
        let dictionaryEntry = firstSystemDictionaryMatch(for: cleanedTerm, kind: resolvedKind)
        let oewnLookup = OpenEnglishWordNetService.shared.lookup(
            term: cleanedTerm,
            kind: resolvedKind,
            manifest: manifest
        )

        let pronunciation = resolvedPronunciation(
            dictionaryPronunciation: dictionaryEntry?.pronunciation ?? oewnLookup?.pronunciation ?? "",
            ecdictPhonetic: ecdictRow?.phonetic ?? ""
        )
        let meaningGroups = resolvedMeaningGroups(
            kind: resolvedKind,
            ecdictTranslation: ecdictRow?.translation,
            ecdictPOS: ecdictRow?.pos,
            dictionaryGlosses: dictionaryEntry?.chineseGlosses ?? [],
            dictionaryPartOfSpeech: dictionaryEntry?.partOfSpeech,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        let partOfSpeech = MeaningGroup.primaryPartOfSpeech(
            from: meaningGroups,
            fallback: resolvedPartOfSpeech(
                kind: resolvedKind,
                ecdictPOS: ecdictRow?.pos,
                dictionaryPartOfSpeech: dictionaryEntry?.partOfSpeech
            )
        )
        let meanings = MeaningGroup.flattenedMeanings(
            from: meaningGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        let englishDefinitions = Array(
            (resolvedEnglishDefinitions(from: ecdictRow?.definition ?? "") + (oewnLookup?.englishDefinitions ?? []))
                .uniqued()
                .prefix(6)
        )
        let englishSynonyms = Array((oewnLookup?.englishSynonyms ?? []).uniqued().prefix(8))
        let inflectionLines = Array(
            ((ecdictRow.map {
                resolvedInflectionLines(query: cleanedTerm, matchedRow: $0, kind: resolvedKind)
            } ?? []) + (oewnLookup?.inflectionLines ?? []))
            .uniqued()
            .prefix(6)
        )
        let referenceTags = ecdictRow.map(resolvedReferenceTags(from:)) ?? []

        guard !meanings.isEmpty
            || !pronunciation.isEmpty
            || !englishDefinitions.isEmpty
            || !englishSynonyms.isEmpty
            || !inflectionLines.isEmpty
            || !referenceTags.isEmpty else {
            return nil
        }

        var sourceComponents: [LookupSourceComponentKind] = []
        if ecdictRow != nil {
            sourceComponents.append(.ecdict)
        }
        if dictionaryEntry != nil {
            sourceComponents.append(.systemDictionary)
        }
        if oewnLookup != nil {
            sourceComponents.append(.openEnglishWordNet)
        }

        return OfflineLexiconCore(
            pronunciation: pronunciation,
            partOfSpeech: partOfSpeech,
            meanings: meanings,
            meaningGroups: meaningGroups,
            collocations: [],
            englishDefinitions: englishDefinitions,
            englishSynonyms: englishSynonyms,
            inflectionLines: inflectionLines,
            referenceTags: referenceTags,
            sourceComponents: sourceComponents.isEmpty ? [.fallback] : sourceComponents
        )
    }

    func lookupEnglishCore(term: String, kind: EntryKind, manifest: OfflineResourceManifest) -> OfflineLexiconCore? {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return nil
        }

        let resolvedKind = effectiveLookupKind(for: cleanedTerm, requestedKind: kind)

        let ecdictRow = firstECDICTMatch(for: cleanedTerm, kind: resolvedKind, manifest: manifest)
        let dictionaryEntry = firstSystemDictionaryMatch(for: cleanedTerm, kind: resolvedKind)
        let oewnLookup = OpenEnglishWordNetService.shared.lookup(
            term: cleanedTerm,
            kind: resolvedKind,
            manifest: manifest
        )
        let meaningGroups = resolvedMeaningGroups(
            kind: resolvedKind,
            ecdictTranslation: ecdictRow?.translation,
            ecdictPOS: ecdictRow?.pos,
            dictionaryGlosses: dictionaryEntry?.chineseGlosses ?? [],
            dictionaryPartOfSpeech: dictionaryEntry?.partOfSpeech,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        let partOfSpeech = MeaningGroup.primaryPartOfSpeech(
            from: meaningGroups,
            fallback: resolvedPartOfSpeech(
                kind: resolvedKind,
                ecdictPOS: ecdictRow?.pos,
                dictionaryPartOfSpeech: dictionaryEntry?.partOfSpeech
            )
        )
        let meanings = MeaningGroup.flattenedMeanings(
            from: meaningGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        let pronunciation = resolvedPronunciation(
            dictionaryPronunciation: dictionaryEntry?.pronunciation ?? oewnLookup?.pronunciation ?? "",
            ecdictPhonetic: ecdictRow?.phonetic ?? ""
        )
        let collocations = Array(
            ((dictionaryEntry?.collocations ?? []) + relatedECDICTPhrases(
                for: ecdictRow?.word ?? cleanedTerm,
                databasePath: manifest.ecdictDatabasePath
            ))
            .uniqued()
        )
        let englishDefinitions = Array(
            (resolvedEnglishDefinitions(from: ecdictRow?.definition ?? "") + (oewnLookup?.englishDefinitions ?? []))
                .uniqued()
                .prefix(6)
        )
        let englishSynonyms = Array((oewnLookup?.englishSynonyms ?? []).uniqued().prefix(8))
        let inflectionLines = Array(
            ((ecdictRow.map {
                resolvedInflectionLines(query: cleanedTerm, matchedRow: $0, kind: resolvedKind)
            } ?? []) + (oewnLookup?.inflectionLines ?? []))
            .uniqued()
            .prefix(6)
        )
        let referenceTags = ecdictRow.map(resolvedReferenceTags(from:)) ?? []

        var sourceComponents: [LookupSourceComponentKind] = []
        if ecdictRow != nil {
            sourceComponents.append(.ecdict)
        }
        if dictionaryEntry != nil {
            sourceComponents.append(.systemDictionary)
        }
        if oewnLookup != nil {
            sourceComponents.append(.openEnglishWordNet)
        }

        guard !meanings.isEmpty
            || !pronunciation.isEmpty
            || !collocations.isEmpty
            || !englishDefinitions.isEmpty
            || !englishSynonyms.isEmpty
            || !inflectionLines.isEmpty
            || !referenceTags.isEmpty else {
            return nil
        }

        return OfflineLexiconCore(
            pronunciation: pronunciation,
            partOfSpeech: partOfSpeech,
            meanings: meanings,
            meaningGroups: meaningGroups,
            collocations: Array(collocations.prefix(5)),
            englishDefinitions: Array(englishDefinitions.prefix(4)),
            englishSynonyms: Array(englishSynonyms.prefix(8)),
            inflectionLines: Array(inflectionLines.prefix(6)),
            referenceTags: Array(referenceTags.prefix(8)),
            sourceComponents: sourceComponents.isEmpty ? [.fallback] : sourceComponents
        )
    }

    func hasEnglishLookupHit(term: String, kind: EntryKind, manifest: OfflineResourceManifest) -> Bool {
        lookupEnglishCore(term: term, kind: kind, manifest: manifest) != nil
            || firstSystemDictionaryMatch(for: term, kind: kind) != nil
            || OpenEnglishWordNetService.shared.hasLookupHit(term: term, kind: kind, manifest: manifest)
    }

    func lookupSuggestions(
        term: String,
        kind: EntryKind,
        manifest: OfflineResourceManifest,
        limit: Int = 8
    ) -> [LookupSuggestion] {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind != .sentence,
              cleanedTerm.count >= 2,
              containsChineseCharacters(in: cleanedTerm) == false else {
            return []
        }

        let resolvedKind = effectiveLookupKind(for: cleanedTerm, requestedKind: kind)

        var suggestions: [LookupSuggestion] = []

        if resolvedKind == .word {
            for candidate in Array(englishLookupCandidates(for: cleanedTerm, kind: resolvedKind).dropFirst()) {
                guard let row = lookupECDICT(term: candidate, databasePath: manifest.ecdictDatabasePath) else {
                    continue
                }

                guard row.word.caseInsensitiveCompare(cleanedTerm) != .orderedSame else {
                    continue
                }

                suggestions.append(
                    LookupSuggestion(
                        term: row.word,
                        preview: preferredChineseMeaning(from: row, kind: row.word.contains(" ") ? .phrase : .word),
                        reason: .inflection,
                        kind: row.word.contains(" ") ? .phrase : .word
                    )
                )
            }
        }

        for row in lookupECDICTPrefixMatches(prefix: cleanedTerm, databasePath: manifest.ecdictDatabasePath, limit: max(limit * 3, 18)) {
            guard row.word.caseInsensitiveCompare(cleanedTerm) != .orderedSame else {
                continue
            }

            let isPhrase = row.word.contains(" ") || row.word.contains("-")
            suggestions.append(
                LookupSuggestion(
                    term: row.word,
                    preview: preferredChineseMeaning(from: row, kind: isPhrase ? .phrase : resolvedKind),
                    reason: isPhrase ? .phraseExpansion : .prefix,
                    kind: isPhrase ? .phrase : resolvedKind
                )
            )
        }

        suggestions.append(
            contentsOf: OpenEnglishWordNetService.shared.suggestions(
                term: cleanedTerm,
                kind: resolvedKind,
                manifest: manifest,
                limit: max(limit * 2, 10)
            )
        )

        return Array(
            suggestions
                .compactMap { validatedSuggestion($0, originalTerm: cleanedTerm, manifest: manifest) }
                .uniqued(by: { "\($0.kind.rawValue)::\($0.term.lowercased())" })
                .prefix(limit)
        )
    }

    func lookupEnglishExamples(
        term: String,
        manifest: OfflineResourceManifest,
        limit: Int = EntryCandidateDefaults.exampleChoiceCount
    ) -> [LookupExample] {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return []
        }

        return lookupTatoebaExamples(
            term: cleanedTerm,
            databasePath: manifest.tatoebaDatabasePath,
            limit: limit
        )
    }

    func reverseLookupChinese(_ query: String, manifest: OfflineResourceManifest, limit: Int = 8) -> [ReverseLookupCandidate] {
        reverseLookupChinese(query, manifest: manifest, limit: limit, exactOnly: false)
    }

    func exactReverseLookupChinese(_ query: String, manifest: OfflineResourceManifest, limit: Int = 8) -> [ReverseLookupCandidate] {
        reverseLookupChinese(query, manifest: manifest, limit: limit, exactOnly: true)
    }

    private func reverseLookupChinese(
        _ query: String,
        manifest: OfflineResourceManifest,
        limit: Int,
        exactOnly: Bool
    ) -> [ReverseLookupCandidate] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty, !manifest.cedictDatabasePath.isEmpty else {
            return []
        }

        do {
            let database = try SQLiteDatabase(
                url: URL(fileURLWithPath: manifest.cedictDatabasePath),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            )

            let exactRows = try cedictRows(
                database: database,
                sql: """
                SELECT simplified, traditional, pinyin, english
                FROM cedict_entries
                WHERE simplified = ? OR traditional = ?
                ORDER BY length(simplified) ASC
                LIMIT 24;
                """,
                query: cleanedQuery
            )

            let prefixRows: [(simplified: String, traditional: String, pinyin: String, english: String)]
            if exactRows.isEmpty, !exactOnly {
                prefixRows = try cedictRows(
                    database: database,
                    sql: """
                    SELECT simplified, traditional, pinyin, english
                    FROM cedict_entries
                    WHERE simplified LIKE ? OR traditional LIKE ?
                    ORDER BY length(simplified) ASC
                    LIMIT 24;
                    """,
                    query: "\(cleanedQuery)%"
                )
            } else {
                prefixRows = []
            }

            let containsRows: [(simplified: String, traditional: String, pinyin: String, english: String)]
            if exactRows.isEmpty, prefixRows.isEmpty, !exactOnly, cleanedQuery.count >= 2 {
                containsRows = try cedictRows(
                    database: database,
                    sql: """
                    SELECT simplified, traditional, pinyin, english
                    FROM cedict_entries
                    WHERE simplified LIKE ? OR traditional LIKE ?
                    ORDER BY length(simplified) ASC
                    LIMIT 32;
                    """,
                    query: "%\(cleanedQuery)%"
                )
            } else {
                containsRows = []
            }

            let rows = exactRows.isEmpty
                ? (prefixRows.isEmpty ? containsRows : prefixRows)
                : exactRows

            var candidates: [ReverseLookupCandidate] = []

            for row in rows {
                let englishCandidates = extractEnglishCandidates(from: row.english)
                for english in englishCandidates {
                    let chinese = row.simplified == cleanedQuery ? row.simplified : "\(row.simplified) / \(row.traditional)"
                    candidates.append(
                        ReverseLookupCandidate(
                            english: english,
                            chinese: chinese,
                            pinyin: row.pinyin
                        )
                    )
                }
            }

            return Array(
                candidates
                    .sorted { lhs, rhs in
                        if lhs.chinese != rhs.chinese {
                            return lhs.chinese.count < rhs.chinese.count
                        }

                        if lhs.english != rhs.english {
                            return lhs.english.count < rhs.english.count
                        }

                        return lhs.pinyin < rhs.pinyin
                    }
                    .uniqued(by: { "\($0.english.lowercased())|\($0.chinese)|\($0.pinyin)" })
                    .prefix(limit)
            )
        } catch {
            return []
        }
    }

    private func lookupECDICT(term: String, databasePath: String) -> ECDICTRow? {
        guard !databasePath.isEmpty else {
            return nil
        }

        do {
            let database = try SQLiteDatabase(
                url: URL(fileURLWithPath: databasePath),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            )

            let statement = try database.prepare(
                """
                SELECT word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq, audio
                FROM stardict
                WHERE lower(word) = lower(?)
                LIMIT 1;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, term, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            return ECDICTRow(
                word: sqliteString(statement, column: 0),
                phonetic: sqliteString(statement, column: 1),
                pos: sqliteString(statement, column: 2),
                translation: sqliteString(statement, column: 3),
                definition: sqliteString(statement, column: 4),
                exchange: sqliteString(statement, column: 5),
                collins: sqliteInt(statement, column: 6),
                oxford: sqliteInt(statement, column: 7),
                tag: sqliteString(statement, column: 8),
                bnc: sqliteInt(statement, column: 9),
                frq: sqliteInt(statement, column: 10),
                audio: sqliteString(statement, column: 11)
            )
        } catch {
            return nil
        }
    }

    func localizedCollocations(
        _ rawCollocations: [String],
        manifest: OfflineResourceManifest
    ) -> [String] {
        Array(
            rawCollocations
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniqued()
                .map { phrase in
                    guard let meaning = preferredChineseMeaning(for: phrase, manifest: manifest) else {
                        return phrase
                    }

                    return "\(phrase) · \(meaning)"
                }
                .prefix(5)
        )
    }

    func localizedCollocation(
        _ rawCollocation: String,
        manifest: OfflineResourceManifest
    ) -> String {
        let cleaned = rawCollocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return rawCollocation
        }

        guard let meaning = preferredChineseMeaning(for: cleaned, manifest: manifest) else {
            return cleaned
        }

        return "\(cleaned) · \(meaning)"
    }

    private func preferredChineseMeaning(for term: String, manifest: OfflineResourceManifest) -> String? {
        let ecdictRow = firstECDICTMatch(for: term, kind: term.contains(" ") ? .phrase : .word, manifest: manifest)
        let dictionaryEntry = firstSystemDictionaryMatch(for: term, kind: term.contains(" ") ? .phrase : .word)
        let meaningGroups = resolvedMeaningGroups(
            kind: term.contains(" ") ? .phrase : .word,
            ecdictTranslation: ecdictRow?.translation,
            ecdictPOS: ecdictRow?.pos,
            dictionaryGlosses: dictionaryEntry?.chineseGlosses ?? [],
            dictionaryPartOfSpeech: dictionaryEntry?.partOfSpeech,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        let meanings = MeaningGroup.flattenedMeanings(from: meaningGroups, maxCount: EntryCandidateDefaults.meaningChoiceCount)

        return meanings.first
    }

    private func preferredChineseMeaning(from row: ECDICTRow, kind: EntryKind) -> String {
        let meaningGroups = resolvedMeaningGroups(
            kind: kind,
            ecdictTranslation: row.translation,
            ecdictPOS: row.pos,
            dictionaryGlosses: [],
            dictionaryPartOfSpeech: nil,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        let meanings = MeaningGroup.flattenedMeanings(
            from: meaningGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )

        return meanings.first ?? ""
    }

    private func validatedSuggestion(
        _ suggestion: LookupSuggestion,
        originalTerm: String,
        manifest: OfflineResourceManifest
    ) -> LookupSuggestion? {
        let cleanedTerm = suggestion.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty,
              cleanedTerm.caseInsensitiveCompare(originalTerm) != .orderedSame else {
            return nil
        }

        let chinesePreview = preferredChineseMeaning(for: cleanedTerm, manifest: manifest)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackPreview = suggestion.preview.trimmingCharacters(in: .whitespacesAndNewlines)

        if suggestion.kind == .phrase && chinesePreview.isEmpty {
            return nil
        }

        let resolvedPreview = chinesePreview.isEmpty ? fallbackPreview : chinesePreview
        guard !resolvedPreview.isEmpty else {
            return nil
        }

        return LookupSuggestion(
            term: cleanedTerm,
            preview: resolvedPreview,
            reason: suggestion.reason,
            kind: suggestion.kind
        )
    }

    private func lookupTatoebaExamples(term: String, databasePath: String, limit: Int) -> [LookupExample] {
        guard !databasePath.isEmpty else {
            return []
        }

        let quotedTerm = "\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\""

        do {
            let database = try SQLiteDatabase(
                url: URL(fileURLWithPath: databasePath),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            )

            let statement = try database.prepare(
                """
                SELECT eng.text, cmn.text
                FROM english_sentences_fts AS fts
                JOIN sentences AS eng ON eng.id = fts.rowid
                JOIN bilingual_links AS links ON links.eng_id = eng.id
                JOIN sentences AS cmn ON cmn.id = links.cmn_id
                WHERE fts.text MATCH ?
                ORDER BY length(eng.text) ASC
                LIMIT ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, quotedTerm, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var examples: [LookupExample] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let english = sqliteString(statement, column: 0)
                let chinese = sqliteString(statement, column: 1)
                guard !english.isEmpty, !chinese.isEmpty else {
                    continue
                }

                examples.append(LookupExample(english: english, chinese: chinese))
            }

            return examples
        } catch {
            return []
        }
    }

    private func resolvedPartOfSpeech(kind: EntryKind, ecdictPOS: String?, dictionaryPartOfSpeech: String?) -> String {
        if kind == .sentence {
            return "句子"
        }

        if kind == .phrase {
            return "短语"
        }

        if let dictionaryPartOfSpeech, !dictionaryPartOfSpeech.isEmpty {
            return dictionaryPartOfSpeech
        }

        let primaryCode = primaryPOSCode(from: ecdictPOS ?? "")

        switch primaryCode {
        case "n":
            return "名词"
        case "v":
            return "动词"
        case "a", "j":
            return "形容词"
        case "d":
            return "副词"
        case "p":
            return "介词"
        case "r":
            return "代词"
        case "c":
            return "连词"
        case "u":
            return "助词"
        case "m":
            return "数词"
        case "q":
            return "量词"
        default:
            return "单词"
        }
    }

    private func resolvedMeaningGroups(
        kind: EntryKind,
        ecdictTranslation: String?,
        ecdictPOS: String?,
        dictionaryGlosses: [String],
        dictionaryPartOfSpeech: String?,
        maxMeanings: Int
    ) -> [MeaningGroup] {
        let fallbackPartOfSpeech = resolvedPartOfSpeech(
            kind: kind,
            ecdictPOS: ecdictPOS,
            dictionaryPartOfSpeech: dictionaryPartOfSpeech
        )

        var groups = parseECDICTMeaningGroups(
            from: ecdictTranslation ?? "",
            fallbackPartOfSpeech: fallbackPartOfSpeech
        )

        let dictionaryMeanings = dictionaryGlosses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !dictionaryMeanings.isEmpty {
            groups.append(
                MeaningGroup(
                    partOfSpeech: dictionaryPartOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? dictionaryPartOfSpeech!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : fallbackPartOfSpeech,
                    meanings: dictionaryMeanings
                )
            )
        }

        let preferredPartOfSpeechOrder = preferredPartOfSpeechOrder(
            from: ecdictPOS,
            dictionaryPartOfSpeech: dictionaryPartOfSpeech
        )

        return MeaningGroup.normalized(
            orderedMeaningGroups(groups, preferredPartOfSpeechOrder: preferredPartOfSpeechOrder),
            fallbackPartOfSpeech: fallbackPartOfSpeech,
            maxMeanings: maxMeanings
        )
    }

    private func preferredPartOfSpeechOrder(from ecdictPOS: String?, dictionaryPartOfSpeech: String?) -> [String] {
        var orderedLabels = (ecdictPOS ?? "")
            .split(separator: "/")
            .compactMap { rawPart -> (label: String, score: Int, order: Int)? in
                let pieces = rawPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard let code = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !code.isEmpty else {
                    return nil
                }

                let label = localizedPartOfSpeech(code: code)
                let score = pieces.count > 1 ? Int(pieces[1]) ?? 0 : 0
                let order = (ecdictPOS ?? "")
                    .split(separator: "/")
                    .firstIndex(of: rawPart) ?? 0
                return (label: label, score: score, order: order)
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.order < $1.order
                }
                return $0.score > $1.score
            }
            .map(\.label)

        if let dictionaryPartOfSpeech {
            let cleanedDictionaryPartOfSpeech = dictionaryPartOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedDictionaryPartOfSpeech.isEmpty,
               !orderedLabels.contains(where: { $0.caseInsensitiveCompare(cleanedDictionaryPartOfSpeech) == .orderedSame }) {
                orderedLabels.append(cleanedDictionaryPartOfSpeech)
            }
        }

        return orderedLabels
    }

    private func localizedPartOfSpeech(code: String) -> String {
        switch code.lowercased() {
        case "n", "noun":
            return "名词"
        case "v", "vt", "vi", "verb", "aux", "pa", "pp":
            return "动词"
        case "adj", "a", "adjective":
            return "形容词"
        case "adv", "ad", "adverb":
            return "副词"
        case "prep", "preposition":
            return "介词"
        case "pron", "pronoun":
            return "代词"
        case "conj", "conjunction":
            return "连词"
        case "int", "interjection":
            return "感叹词"
        case "num", "numeral":
            return "数词"
        case "q", "clf", "classifier":
            return "量词"
        case "phr", "phrase":
            return "短语"
        default:
            return "单词"
        }
    }

    private func orderedMeaningGroups(
        _ groups: [MeaningGroup],
        preferredPartOfSpeechOrder: [String]
    ) -> [MeaningGroup] {
        guard !preferredPartOfSpeechOrder.isEmpty else {
            return groups
        }

        return groups.enumerated().sorted { left, right in
            let leftRank = preferredPartOfSpeechOrder.firstIndex {
                $0.caseInsensitiveCompare(left.element.partOfSpeech) == .orderedSame
            } ?? Int.max
            let rightRank = preferredPartOfSpeechOrder.firstIndex {
                $0.caseInsensitiveCompare(right.element.partOfSpeech) == .orderedSame
            } ?? Int.max

            if leftRank == rightRank {
                return left.offset < right.offset
            }

            return leftRank < rightRank
        }
        .map(\.element)
    }

    private func resolvedPronunciation(dictionaryPronunciation: String, ecdictPhonetic: String) -> String {
        let trimmedDictionaryPronunciation = dictionaryPronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDictionaryPronunciation.isEmpty {
            return trimmedDictionaryPronunciation
        }

        let trimmedECDICT = ecdictPhonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedECDICT.isEmpty else {
            return ""
        }

        return "/\(trimmedECDICT)/"
    }

    private func resolvedEnglishDefinitions(from definition: String, maxCount: Int = 4) -> [String] {
        let cleanedDefinition = definition
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedDefinition.isEmpty else {
            return []
        }

        var results: [String] = []
        var seen = Set<String>()

        for line in cleanedDefinition
            .split(separator: "\n")
            .flatMap({ normalizedEnglishDefinitionLines(from: String($0)) })
            .map(sanitizeEnglishDefinitionText(_:))
            .filter({ !$0.isEmpty }) {
            let key = normalizedEnglishDefinitionDedupKey(line)
            guard !key.isEmpty, seen.insert(key).inserted else {
                continue
            }

            results.append(line)
            if results.count >= maxCount {
                break
            }
        }

        return results
    }

    private func normalizedEnglishDefinitionLines(from text: String) -> [String] {
        let normalized = sanitizeTranslationText(text)
            .replacingOccurrences(
                of: #"\s+(?=(?:vt|vi|verb|v|noun|n|adj|a|adv|ad|prep|pron|conj|int|aux)\.)"#,
                with: "\n",
                options: .regularExpression
            )

        return normalized
            .split(separator: "\n")
            .map { sanitizeTranslationText(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func sanitizeEnglishDefinitionText(_ text: String) -> String {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("synonyms:") || lowered.hasPrefix("antonyms:") {
            return ""
        }

        let stripped = consumeLeadingPartOfSpeech(from: sanitizeTranslationText(text)).1
            .replacingOccurrences(
                of: #"^(?:[a-z]|adj|adv|n|v|vt|vi|verb|noun|adjective|adverb)\s+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;，；"))

        guard !stripped.isEmpty,
              containsChineseCharacters(in: stripped) == false,
              stripped.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return ""
        }

        return stripped
    }

    private func normalizedEnglishDefinitionDedupKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedInflectionLines(
        query: String,
        matchedRow: ECDICTRow,
        kind: EntryKind
    ) -> [String] {
        guard kind == .word else {
            return []
        }

        let exchangeMap = parsedExchangeMap(from: matchedRow.exchange)
        guard exchangeMap.isEmpty == false else {
            return []
        }

        var lines: [String] = []
        let lemma = exchangeMap["0"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let relationFlags = exchangeMap["1"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !lemma.isEmpty, lemma.caseInsensitiveCompare(matchedRow.word) != .orderedSame {
            lines.append("原形：\(lemma)")

            let relation = localizedInflectionRelation(from: relationFlags)
            if !relation.isEmpty {
                lines.append("当前词形：\(lemma) 的\(relation)")
            }
        }

        let thirdPersonSingular = exchangeMap["3"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plural = exchangeMap["s"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let presentParticiple = exchangeMap["i"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let past = exchangeMap["p"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pastParticiple = exchangeMap["d"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let comparative = exchangeMap["r"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let superlative = exchangeMap["t"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !thirdPersonSingular.isEmpty {
            lines.append("第三人称单数：\(thirdPersonSingular)")
        }

        if !presentParticiple.isEmpty {
            lines.append("现在分词：\(presentParticiple)")
        }

        if !past.isEmpty, !pastParticiple.isEmpty, past.caseInsensitiveCompare(pastParticiple) == .orderedSame {
            lines.append("过去式 / 过去分词：\(past)")
        } else {
            if !past.isEmpty {
                lines.append("过去式：\(past)")
            }
            if !pastParticiple.isEmpty {
                lines.append("过去分词：\(pastParticiple)")
            }
        }

        if !plural.isEmpty, plural.caseInsensitiveCompare(thirdPersonSingular) != .orderedSame {
            lines.append("复数：\(plural)")
        }

        if !comparative.isEmpty {
            lines.append("比较级：\(comparative)")
        }

        if !superlative.isEmpty {
            lines.append("最高级：\(superlative)")
        }

        return Array(lines.uniqued().prefix(6))
    }

    private func parsedExchangeMap(from exchange: String) -> [String: String] {
        exchange
            .split(separator: "/")
            .reduce(into: [String: String]()) { result, part in
                let segments = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard segments.count == 2 else {
                    return
                }

                let key = String(segments[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(segments[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else {
                    return
                }

                result[key] = value
            }
    }

    private func localizedInflectionRelation(from flags: String) -> String {
        let localizedFlags = flags.compactMap { character -> String? in
            switch character {
            case "p":
                return "过去式"
            case "d":
                return "过去分词"
            case "i":
                return "现在分词"
            case "3":
                return "第三人称单数"
            case "s":
                return "复数"
            case "r":
                return "比较级"
            case "t":
                return "最高级"
            default:
                return nil
            }
        }

        guard !localizedFlags.isEmpty else {
            return ""
        }

        return localizedFlags.uniqued().joined(separator: " / ")
    }

    private func resolvedReferenceTags(from row: ECDICTRow) -> [String] {
        var tags: [String] = []

        if let collins = row.collins, collins > 0 {
            tags.append("柯林斯 \(collins) 星")
        }

        if let oxford = row.oxford, oxford > 0 {
            tags.append("牛津核心词")
        }

        tags.append(contentsOf: localizedExamTags(from: row.tag))

        if let frq = row.frq, frq > 0 {
            tags.append("现代词频 #\(frq)")
        }

        if let bnc = row.bnc, bnc > 0 {
            tags.append("BNC #\(bnc)")
        }

        return Array(tags.uniqued().prefix(8))
    }

    private func localizedExamTags(from rawTag: String) -> [String] {
        let mapping: [String: String] = [
            "zk": "中考",
            "gk": "高考",
            "cet4": "四级",
            "cet6": "六级",
            "ky": "考研",
            "toefl": "TOEFL",
            "ielts": "IELTS",
            "gre": "GRE"
        ]

        return rawTag
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
            .compactMap { mapping[$0] ?? ($0.isEmpty ? nil : $0.uppercased()) }
            .uniqued()
    }

    private func relatedECDICTPhrases(
        for baseTerm: String,
        databasePath: String,
        limit: Int = 5
    ) -> [String] {
        let cleanedBase = baseTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBase.isEmpty, cleanedBase.count >= 3, !databasePath.isEmpty else {
            return []
        }

        let rows = lookupECDICTPhraseMatches(baseTerm: cleanedBase, databasePath: databasePath, limit: max(limit * 3, 12))

        return Array(
            rows.compactMap { row -> String? in
                let cleanedWord = row.word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanedWord.caseInsensitiveCompare(cleanedBase) != .orderedSame else {
                    return nil
                }

                let meaning = preferredChineseMeaning(from: row, kind: .phrase)
                return meaning.isEmpty ? cleanedWord : "\(cleanedWord) · \(meaning)"
            }
            .uniqued()
            .prefix(limit)
        )
    }

    private func lookupECDICTPrefixMatches(prefix: String, databasePath: String, limit: Int) -> [ECDICTRow] {
        guard !databasePath.isEmpty else {
            return []
        }

        do {
            let database = try SQLiteDatabase(
                url: URL(fileURLWithPath: databasePath),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            )
            let statement = try database.prepare(
                """
                SELECT word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq, audio
                FROM stardict
                WHERE word LIKE ? COLLATE NOCASE
                ORDER BY
                    CASE
                        WHEN lower(word) = lower(?) THEN 0
                        WHEN lower(word) LIKE lower(?) || ' %' THEN 1
                        WHEN lower(word) LIKE lower(?) || '-%' THEN 1
                        ELSE 2
                    END,
                    CASE WHEN frq IS NULL OR frq = 0 THEN 1 ELSE 0 END,
                    frq ASC,
                    length(word) ASC
                LIMIT ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, "\(prefix)%", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, prefix, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, prefix, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, prefix, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 5, Int32(limit))

            return collectECDICTRows(from: statement)
        } catch {
            return []
        }
    }

    private func lookupECDICTPhraseMatches(baseTerm: String, databasePath: String, limit: Int) -> [ECDICTRow] {
        guard !databasePath.isEmpty else {
            return []
        }

        do {
            let database = try SQLiteDatabase(
                url: URL(fileURLWithPath: databasePath),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            )
            let statement = try database.prepare(
                """
                SELECT word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq, audio
                FROM stardict
                WHERE word LIKE ? COLLATE NOCASE OR word LIKE ? COLLATE NOCASE
                ORDER BY
                    CASE WHEN frq IS NULL OR frq = 0 THEN 1 ELSE 0 END,
                    frq ASC,
                    length(word) ASC
                LIMIT ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, "\(baseTerm) %", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, "\(baseTerm)-%", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 3, Int32(limit))

            return collectECDICTRows(from: statement)
        } catch {
            return []
        }
    }

    private func collectECDICTRows(from statement: OpaquePointer?) -> [ECDICTRow] {
        var rows: [ECDICTRow] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                ECDICTRow(
                    word: sqliteString(statement, column: 0),
                    phonetic: sqliteString(statement, column: 1),
                    pos: sqliteString(statement, column: 2),
                    translation: sqliteString(statement, column: 3),
                    definition: sqliteString(statement, column: 4),
                    exchange: sqliteString(statement, column: 5),
                    collins: sqliteInt(statement, column: 6),
                    oxford: sqliteInt(statement, column: 7),
                    tag: sqliteString(statement, column: 8),
                    bnc: sqliteInt(statement, column: 9),
                    frq: sqliteInt(statement, column: 10),
                    audio: sqliteString(statement, column: 11)
                )
            )
        }

        return rows
    }

    private func primaryPOSCode(from text: String) -> String {
        let parts = text.split(separator: "/")
        var bestCode = ""
        var bestScore = Int.min

        for part in parts {
            let segments = part.split(separator: ":")
            guard let code = segments.first else {
                continue
            }

            let score = segments.count > 1 ? Int(segments[1]) ?? 0 : 0
            if score > bestScore {
                bestScore = score
                bestCode = String(code)
            }
        }

        return bestCode
    }

    private func parseECDICTMeaningGroups(from translation: String, fallbackPartOfSpeech: String) -> [MeaningGroup] {
        let cleanedTranslation = translation
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard !cleanedTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let lines = cleanedTranslation
            .split(separator: "\n")
            .flatMap { normalizedMeaningGroupLines(from: String($0)) }
            .filter { !$0.isEmpty }

        let parsedGroups = lines.compactMap { line -> MeaningGroup? in
            let (taggedPartOfSpeech, strippedText) = consumeLeadingPartOfSpeech(from: line)
            let meanings = splitMeaningSegments(strippedText)
                .map(sanitizeMeaningText)
                .filter { !$0.isEmpty }

            guard !meanings.isEmpty else {
                return nil
            }

            let partOfSpeech = taggedPartOfSpeech
                ?? inferredPartOfSpeech(from: strippedText)
                ?? fallbackPartOfSpeech

            return MeaningGroup(partOfSpeech: partOfSpeech, meanings: meanings)
        }

        if !parsedGroups.isEmpty {
            return parsedGroups
        }

        let fallbackMeanings = splitMeaningSegments(cleanedTranslation)
            .map(sanitizeMeaningText)
            .filter { !$0.isEmpty }

        guard !fallbackMeanings.isEmpty else {
            return []
        }

        return [
            MeaningGroup(
                partOfSpeech: inferredPartOfSpeech(from: cleanedTranslation) ?? fallbackPartOfSpeech,
                meanings: fallbackMeanings
            )
        ]
    }

    private func sanitizeTranslationText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedMeaningGroupLines(from text: String) -> [String] {
        let normalized = sanitizeTranslationText(text)
            .replacingOccurrences(
                of: #"\s+(?=(?:vt|vi|verb|v|noun|n|adj|a|adv|ad|prep|pron|conj|int|aux|pa|pp)\.)"#,
                with: "\n",
                options: .regularExpression
            )

        return normalized
            .split(separator: "\n")
            .map { sanitizeTranslationText(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func consumeLeadingPartOfSpeech(from text: String) -> (String?, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags: [(String, String)] = [
            ("transitive verb.", "动词"),
            ("intransitive verb.", "动词"),
            ("adjective.", "形容词"),
            ("adverb.", "副词"),
            ("preposition.", "介词"),
            ("pronoun.", "代词"),
            ("conjunction.", "连词"),
            ("interjection.", "感叹词"),
            ("auxiliary verb.", "动词"),
            ("vt.", "动词"),
            ("vi.", "动词"),
            ("verb.", "动词"),
            ("v.", "动词"),
            ("noun.", "名词"),
            ("n.", "名词"),
            ("adj.", "形容词"),
            ("a.", "形容词"),
            ("adv.", "副词"),
            ("ad.", "副词"),
            ("prep.", "介词"),
            ("pron.", "代词"),
            ("conj.", "连词"),
            ("int.", "感叹词"),
            ("aux.", "动词"),
            ("pa.", "动词"),
            ("pp.", "动词")
        ]

        let lowercased = trimmed.lowercased()
        for (tag, localizedPartOfSpeech) in tags {
            guard lowercased.hasPrefix(tag) else {
                continue
            }

            let stripped = trimmed.dropFirst(tag.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return (localizedPartOfSpeech, stripped)
        }

        return (nil, trimmed)
    }

    private func inferredPartOfSpeech(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.contains("过去式")
            || trimmed.contains("过去分词")
            || trimmed.contains("现在分词")
            || trimmed.contains("第三人称单数")
            || trimmed.contains("动名词")
            || trimmed.contains("原形")
            || trimmed.contains("不定式") {
            return "动词"
        }

        return nil
    }

    private func splitMeaningSegments(_ text: String) -> [String] {
        let cleaned = sanitizeTranslationText(text)
        guard !cleaned.isEmpty else {
            return []
        }

        var segments: [String] = []
        var current = ""
        var depth = 0

        for character in cleaned {
            switch character {
            case "(", "[", "{":
                depth += 1
                current.append(character)
            case ")", "]", "}":
                depth = max(0, depth - 1)
                current.append(character)
            case ",", ";", "，", "；":
                if depth == 0 {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        segments.append(trimmed)
                    }
                    current.removeAll(keepingCapacity: true)
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            segments.append(trimmed)
        }

        return segments
            .flatMap(expandedMeaningSegments(from:))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func sanitizeMeaningText(_ text: String) -> String {
        let stripped = consumeLeadingPartOfSpeech(from: sanitizeTranslationText(text)).1
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;，；"))

        guard !stripped.isEmpty else {
            return ""
        }

        let markerOnly = stripped
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let junkMarkers: Set<String> = [
            "pa", "pp", "pa", "pp", "vt", "vi", "v", "n", "a", "adj", "adv", "ad", "prep", "pron", "conj", "aux"
        ]

        if junkMarkers.contains(markerOnly) {
            return ""
        }

        if stripped.count <= 4,
           containsChineseCharacters(in: stripped) == false,
           stripped.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.punctuationCharacters).contains($0) }) {
            return ""
        }

        if containsChineseCharacters(in: stripped) == false,
           inferredPartOfSpeech(from: stripped) == nil {
            return ""
        }

        return stripped
    }

    private func expandedMeaningSegments(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if containsChineseCharacters(in: trimmed),
           containsLatinLetters(in: trimmed) == false,
           trimmed.contains(where: \.isWhitespace) {
            let expanded = trimmed
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if expanded.count > 1 {
                return expanded
            }
        }

        return [trimmed]
    }

    private func containsLatinLetters(in text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.value < 128 }
    }

    private func effectiveLookupKind(for term: String, requestedKind: EntryKind) -> EntryKind {
        guard requestedKind == .phrase else {
            return requestedKind
        }

        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return requestedKind
        }

        if cleanedTerm.contains(" ") || cleanedTerm.contains("-") || containsChineseCharacters(in: cleanedTerm) {
            return requestedKind
        }

        return .word
    }

    private func containsChineseCharacters(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private func cedictRows(database: SQLiteDatabase, sql: String, query: String) throws -> [(simplified: String, traditional: String, pinyin: String, english: String)] {
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, query, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, query, -1, SQLITE_TRANSIENT)

        var rows: [(simplified: String, traditional: String, pinyin: String, english: String)] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((
                simplified: sqliteString(statement, column: 0),
                traditional: sqliteString(statement, column: 1),
                pinyin: sqliteString(statement, column: 2),
                english: sqliteString(statement, column: 3)
            ))
        }

        return rows
    }

    private func extractEnglishCandidates(from english: String) -> [String] {
        english
            .split(separator: "/")
            .flatMap { part in
                part
                    .replacingOccurrences(of: "(fig.)", with: "")
                    .replacingOccurrences(of: "(lit.)", with: "")
                    .split(whereSeparator: { ";,，；".contains($0) })
                    .map(String.init)
            }
            .flatMap(normalizedEnglishCandidateVariants(from:))
            .uniqued()
    }

    private func firstECDICTMatch(
        for term: String,
        kind: EntryKind,
        manifest: OfflineResourceManifest
    ) -> ECDICTRow? {
        for candidate in englishLookupCandidates(for: term, kind: kind) {
            if let row = lookupECDICT(term: candidate, databasePath: manifest.ecdictDatabasePath) {
                return row
            }
        }

        return nil
    }

    private func firstSystemDictionaryMatch(for term: String, kind: EntryKind) -> LocalDictionaryEntry? {
        for candidate in englishLookupCandidates(for: term, kind: kind) {
            if let entry = SystemDictionaryService.shared.entry(for: candidate) {
                return entry
            }
        }

        return nil
    }

    private func englishLookupCandidates(for term: String, kind: EntryKind) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var candidates: [String] = [trimmed]
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
            let spaced = normalizedHyphen.replacingOccurrences(of: "-", with: " ")
            let hyphenated = normalizedHyphen.replacingOccurrences(of: " ", with: "-")
            candidates.append(spaced)
            candidates.append(hyphenated)
        } else {
            candidates.append(contentsOf: inflectedEnglishCandidates(from: normalizedHyphen))
        }

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func inflectedEnglishCandidates(from term: String) -> [String] {
        let lowercased = term.localizedLowercase
        guard !lowercased.isEmpty else {
            return []
        }

        var candidates: [String] = []
        let irregulars: [String: [String]] = [
            "better": ["good"],
            "best": ["good"],
            "worse": ["bad"],
            "worst": ["bad"],
            "went": ["go"],
            "gone": ["go"],
            "done": ["do"],
            "did": ["do"],
            "taken": ["take"],
            "took": ["take"],
            "made": ["make"],
            "bought": ["buy"],
            "brought": ["bring"],
            "saw": ["see"],
            "seen": ["see"],
            "ran": ["run"],
            "written": ["write"],
            "wrote": ["write"]
        ]

        candidates.append(contentsOf: irregulars[lowercased] ?? [])

        if lowercased.hasSuffix("ies"), lowercased.count > 4 {
            candidates.append(String(lowercased.dropLast(3)) + "y")
        }

        if lowercased.hasSuffix("es"), lowercased.count > 3 {
            candidates.append(String(lowercased.dropLast(2)))
        }

        if lowercased.hasSuffix("s"), lowercased.count > 2 {
            candidates.append(String(lowercased.dropLast(1)))
        }

        if lowercased.hasSuffix("ied"), lowercased.count > 4 {
            candidates.append(String(lowercased.dropLast(3)) + "y")
        }

        if lowercased.hasSuffix("ed"), lowercased.count > 3 {
            let stem = String(lowercased.dropLast(2))
            candidates.append(stem)
            candidates.append(stem + "e")
            if let simplified = droppingTrailingDoubledConsonant(from: stem) {
                candidates.append(simplified)
            }
        }

        if lowercased.hasSuffix("ing"), lowercased.count > 5 {
            let stem = String(lowercased.dropLast(3))
            candidates.append(stem)
            candidates.append(stem + "e")
            if let simplified = droppingTrailingDoubledConsonant(from: stem) {
                candidates.append(simplified)
            }
        }

        if lowercased.hasSuffix("er"), lowercased.count > 4 {
            let stem = String(lowercased.dropLast(2))
            candidates.append(stem)
            candidates.append(stem + "e")
            if stem.hasSuffix("i") {
                candidates.append(String(stem.dropLast()) + "y")
            }
        }

        if lowercased.hasSuffix("est"), lowercased.count > 5 {
            let stem = String(lowercased.dropLast(3))
            candidates.append(stem)
            candidates.append(stem + "e")
            if stem.hasSuffix("i") {
                candidates.append(String(stem.dropLast()) + "y")
            }
        }

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func droppingTrailingDoubledConsonant(from stem: String) -> String? {
        guard stem.count >= 2 else {
            return nil
        }

        let lastTwo = Array(stem.suffix(2))
        guard lastTwo.count == 2, lastTwo[0] == lastTwo[1], "bcdfghjklmnpqrstvwxyz".contains(lastTwo[0]) else {
            return nil
        }

        return String(stem.dropLast())
    }

    private func normalizedEnglishCandidateVariants(from rawValue: String) -> [String] {
        let cleaned = rawValue
            .replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^fig\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^lit\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^fig\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^lit\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty, cleaned.count <= 40 else {
            return []
        }

        let lowercased = cleaned.localizedLowercase
        let blockedPrefixes = [
            "cl:",
            "variant of ",
            "old variant of ",
            "used in ",
            "classifier for ",
            "surname ",
            "abbr. ",
            "abbreviation for ",
            "see also "
        ]

        guard blockedPrefixes.contains(where: { lowercased.hasPrefix($0) }) == false else {
            return []
        }

        guard cleaned.caseInsensitiveCompare("sb") != .orderedSame,
              cleaned.caseInsensitiveCompare("sth") != .orderedSame else {
            return []
        }

        var variants = [cleaned]

        for prefix in ["to ", "a ", "an ", "the "] where lowercased.hasPrefix(prefix) && cleaned.count > prefix.count {
            variants.append(String(cleaned.dropFirst(prefix.count)))
        }

        return variants
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }
}

nonisolated private func sqliteString(_ statement: OpaquePointer?, column: Int32) -> String {
    guard let cString = sqlite3_column_text(statement, column) else {
        return ""
    }

    return String(cString: cString)
}

nonisolated private func sqliteInt(_ statement: OpaquePointer?, column: Int32) -> Int? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
        return nil
    }

    return Int(sqlite3_column_int(statement, column))
}

private extension Array {
    nonisolated func uniqued(by key: (Element) -> String) -> [Element] {
        var seen: Set<String> = []
        return filter { element in
            let value = key(element)
            if seen.contains(value) {
                return false
            }
            seen.insert(value)
            return true
        }
    }
}
