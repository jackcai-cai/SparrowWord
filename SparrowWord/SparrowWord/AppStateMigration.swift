import Foundation

// Static migration, normalization, and offline-lexicon enrichment helpers,
// extracted from AppState.swift to shrink the main type. Pure value transforms
// over models — no instance state.
extension AppState {
    static func normalizedLoadedEntry(_ entry: VocabEntry) -> VocabEntry {
        var normalizedEntry = entry
        normalizedEntry.meaningChoices = normalizedChoiceEntries(
            normalizedEntry.meaningChoices,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        normalizedEntry.meaningGroups = normalizedLoadedMeaningGroups(
            kind: normalizedEntry.kind,
            partOfSpeech: normalizedEntry.partOfSpeech,
            meaningGroups: normalizedEntry.meaningGroups,
            meanings: normalizedEntry.meaningChoices,
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        normalizedEntry.partOfSpeech = MeaningGroup.primaryPartOfSpeech(
            from: normalizedEntry.meaningGroups,
            fallback: normalizedEntry.partOfSpeech
        )
        normalizedEntry.meaningChoices = MeaningGroup.flattenedMeanings(
            from: normalizedEntry.meaningGroups,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        normalizedEntry.generatedExamples = cleanedGeneratedExamples(
            normalizedEntry.generatedExamples,
            term: normalizedEntry.term,
            sourceContext: normalizedEntry.sourceContext
        )

        normalizedEntry.sanitizeSelections()
        return normalizedEntry
    }

    static func normalizedLoadedTrashItem(_ item: TrashItem) -> TrashItem {
        var normalizedItem = item
        if let entry = normalizedItem.entry, entry.status == .inbox {
            normalizedItem.sourceCategory = .captureDraft
        }
        return normalizedItem
    }

    static func normalizedLoadedCaptureDraft(_ draft: CaptureDraft) -> CaptureDraft {
        var normalizedDraft = draft
        normalizedDraft.sanitizeSelections()
        return normalizedDraft
    }

    static func normalizedLoadedLookupHistoryRecord(_ record: LookupHistoryRecord) -> LookupHistoryRecord {
        var normalizedRecord = record
        normalizedRecord.content.meaningGroups = normalizedLoadedMeaningGroups(
            kind: normalizedRecord.content.kind,
            partOfSpeech: normalizedRecord.content.partOfSpeech,
            meaningGroups: normalizedRecord.content.meaningGroups,
            meanings: normalizedRecord.content.meanings
        )
        normalizedRecord.content.partOfSpeech = MeaningGroup.primaryPartOfSpeech(
            from: normalizedRecord.content.meaningGroups,
            fallback: normalizedRecord.content.partOfSpeech
        )
        normalizedRecord.content.meanings = MeaningGroup.flattenedMeanings(
            from: normalizedRecord.content.meaningGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        normalizedRecord.content.examples = normalizedRecord.content.examples.filter { example in
            isFallbackGeneratedExample(example.english, term: normalizedRecord.content.term) == false
        }
        normalizedRecord.statusMessage = normalizedLegacyLookupStatusMessage(normalizedRecord.statusMessage)
        return normalizedRecord
    }

    static func normalizedLoadedReviewHistory(_ records: [ReviewHistoryRecord]) -> [ReviewHistoryRecord] {
        guard !records.isEmpty else {
            return []
        }

        var normalizedRecords = records
        let orderedIndices = normalizedRecords.indices.sorted {
            normalizedRecords[$0].reviewedAt < normalizedRecords[$1].reviewedAt
        }

        let legacySessionGapThreshold: TimeInterval = 180
        var currentLegacySessionID: UUID?
        var currentLegacySessionStartedAt: Date?
        var previousLegacyReviewedAt: Date?

        for index in orderedIndices {
            if normalizedRecords[index].reviewSessionID == nil {
                let reviewedAt = normalizedRecords[index].reviewedAt
                let needsNewLegacySession = currentLegacySessionID == nil
                    || reviewedAt.timeIntervalSince(previousLegacyReviewedAt ?? .distantPast) > legacySessionGapThreshold

                if needsNewLegacySession {
                    currentLegacySessionID = UUID()
                    currentLegacySessionStartedAt = reviewedAt
                }

                normalizedRecords[index].reviewSessionID = currentLegacySessionID
                normalizedRecords[index].reviewSessionStartedAt = currentLegacySessionStartedAt ?? reviewedAt
                previousLegacyReviewedAt = reviewedAt
            } else {
                if normalizedRecords[index].reviewSessionStartedAt == nil {
                    normalizedRecords[index].reviewSessionStartedAt = normalizedRecords[index].reviewedAt
                }

                currentLegacySessionID = nil
                currentLegacySessionStartedAt = nil
                previousLegacyReviewedAt = nil
            }

            normalizedRecords[index].sourceKinds = Array(normalizedRecords[index].sourceKinds.uniqued())
        }

        return normalizedRecords
    }

    static func normalizedLegacyLookupStatusMessage(_ message: String?) -> String? {
        guard let message else {
            return nil
        }

        return message
            .replacingOccurrences(of: "收集箱", with: "学习草稿")
            .replacingOccurrences(of: "未重复加入学习草稿", with: "该词已在词库中")
    }

    static func captureDraftFromLegacyInboxEntry(_ entry: VocabEntry) -> CaptureDraft {
        captureDraft(from: entry)
    }

    static func captureDraft(from entry: VocabEntry) -> CaptureDraft {
        var draft = CaptureDraft(
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            kind: entry.kind,
            term: entry.term,
            sourceContext: entry.sourceContext,
            proficiency: entry.proficiency,
            partOfSpeech: entry.partOfSpeech,
            meaningChoices: entry.meaningChoices,
            selectedMeaningIndexes: entry.selectedMeaningIndexes,
            exampleChoices: entry.generatedExamples,
            selectedExampleIndexes: entry.selectedExampleIndexes,
            notes: entry.notes
        )
        draft.meaningCandidates = captureMeaningCandidates(
            meaningGroups: entry.meaningGroups,
            fallbackPartOfSpeech: entry.partOfSpeech,
            fallbackMeanings: entry.meaningChoices,
            fallbackSelectedIndexes: entry.selectedMeaningIndexes
        )
        draft.sanitizeSelections()
        return draft
    }

    static func migrateLegacyInboxState(
        entries: [VocabEntry],
        captureDrafts: [CaptureDraft],
        trashItems: [TrashItem]
    ) -> (entries: [VocabEntry], captureDrafts: [CaptureDraft], trashItems: [TrashItem], didChange: Bool) {
        var nextEntries = entries
            .filter { $0.status != .inbox }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
        var nextCaptureDrafts = captureDrafts
            .sorted(by: { $0.updatedAt > $1.updatedAt })
        var nextTrashItems = trashItems
        let didChange = entries.contains(where: { $0.status == .inbox })

        let legacyInboxEntries = entries
            .filter { $0.status == .inbox }
            .sorted(by: { $0.updatedAt > $1.updatedAt })

        for legacyEntry in legacyInboxEntries {
            let entryKey = captureDraftStorageKey(for: legacyEntry.term, kind: legacyEntry.kind)

            if let existingLibraryIndex = nextEntries.firstIndex(where: {
                $0.status == .library && captureDraftStorageKey(for: $0.term, kind: $0.kind) == entryKey
            }) {
                nextEntries[existingLibraryIndex] = mergedLibraryEntry(
                    primary: nextEntries[existingLibraryIndex],
                    secondary: legacyEntry
                )
                continue
            }

            if shouldKeepLegacyInboxEntryAsDraft(legacyEntry) {
                nextCaptureDrafts = upsertMigratedCaptureDraft(
                    captureDraftFromLegacyInboxEntry(legacyEntry),
                    into: nextCaptureDrafts
                )
                continue
            }

            var promotedEntry = legacyEntry
            promotedEntry.status = .library
            promotedEntry.sanitizeSelections()
            nextEntries.append(promotedEntry)
        }

        nextEntries.sort { $0.updatedAt > $1.updatedAt }
        nextCaptureDrafts.sort { $0.updatedAt > $1.updatedAt }

        nextTrashItems = nextTrashItems.map { item in
            guard item.sourceCategory == .captureDraft || item.entry?.status == .inbox else {
                return item
            }

            var migratedItem = item
            migratedItem.sourceCategory = .captureDraft
            return migratedItem
        }

        return (nextEntries, nextCaptureDrafts, nextTrashItems, didChange)
    }

    static func shouldKeepLegacyInboxEntryAsDraft(_ entry: VocabEntry) -> Bool {
        if entry.kind == .sentence {
            return true
        }

        if entry.hasSelectedMeaning == false {
            return true
        }

        if containsChineseCharactersForLegacyMigration(entry.preferredMeaning) == false {
            return true
        }

        if containsChineseCharactersForLegacyMigration(entry.sourceContext),
           containsChineseCharactersForLegacyMigration(entry.term) == false,
           entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           entry.hasSelectedExample == false {
            return true
        }

        return false
    }

    static func upsertMigratedCaptureDraft(
        _ draft: CaptureDraft,
        into drafts: [CaptureDraft]
    ) -> [CaptureDraft] {
        var nextDrafts = drafts
        let draftKey = captureDraftStorageKey(for: draft.term, kind: draft.kind)

        if let existingIndex = nextDrafts.firstIndex(where: {
            captureDraftStorageKey(for: $0.term, kind: $0.kind) == draftKey
        }) {
            var mergedDraft = nextDrafts[existingIndex]
            if mergedDraft.sourceContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mergedDraft.sourceContext = draft.sourceContext
            }
            if mergedDraft.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mergedDraft.partOfSpeech = draft.partOfSpeech
            }
            if mergedDraft.meaningChoices.isEmpty {
                mergedDraft.meaningChoices = draft.meaningChoices
                mergedDraft.selectedMeaningIndexes = draft.selectedMeaningIndexes
            }
            if mergedDraft.exampleChoices.isEmpty {
                mergedDraft.exampleChoices = draft.exampleChoices
                mergedDraft.selectedExampleIndexes = draft.selectedExampleIndexes
            }
            if mergedDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mergedDraft.notes = draft.notes
            }
            mergedDraft.proficiency = max(mergedDraft.proficiency, draft.proficiency)
            mergedDraft.updatedAt = max(mergedDraft.updatedAt, draft.updatedAt)
            mergedDraft.sanitizeSelections()
            nextDrafts[existingIndex] = mergedDraft
            return nextDrafts
        }

        nextDrafts.append(draft)
        return nextDrafts
    }

    static func mergedLibraryEntry(primary: VocabEntry, secondary: VocabEntry) -> VocabEntry {
        var mergedEntry = primary

        if !secondary.sourceContext.isEmpty, !mergedEntry.sourceContext.contains(secondary.sourceContext) {
            mergedEntry.sourceContext = [mergedEntry.sourceContext, secondary.sourceContext]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        mergedEntry.meaningChoices = normalizedChoiceEntries(
            mergedEntry.meaningChoices + secondary.meaningChoices,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        mergedEntry.meaningGroups = MeaningGroup.normalized(
            mergedEntry.meaningGroups + secondary.meaningGroups,
            fallbackPartOfSpeech: mergedEntry.partOfSpeech,
            fallbackMeanings: mergedEntry.meaningChoices,
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        mergedEntry.generatedExamples = normalizedChoiceEntries(
            mergedEntry.generatedExamples + secondary.generatedExamples,
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )
        mergedEntry.englishDefinitions = Array((mergedEntry.englishDefinitions + secondary.englishDefinitions).uniqued())
        mergedEntry.englishSynonyms = Array((mergedEntry.englishSynonyms + secondary.englishSynonyms).uniqued())
        mergedEntry.inflectionLines = Array((mergedEntry.inflectionLines + secondary.inflectionLines).uniqued())
        mergedEntry.referenceTags = Array((mergedEntry.referenceTags + secondary.referenceTags).uniqued())
        mergedEntry.notes = [mergedEntry.notes, secondary.notes]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        mergedEntry.proficiency = max(mergedEntry.proficiency, secondary.proficiency)
        mergedEntry.reviewCount += secondary.reviewCount
        mergedEntry.lastReviewedAt = max(
            mergedEntry.lastReviewedAt ?? .distantPast,
            secondary.lastReviewedAt ?? .distantPast
        )
        mergedEntry.status = .library
        mergedEntry.updatedAt = max(mergedEntry.updatedAt, secondary.updatedAt)
        mergedEntry.sanitizeSelections()
        return mergedEntry
    }

    static func captureDraftStorageKey(for term: String, kind: EntryKind) -> String {
        "\(kind.rawValue)::\(term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func containsChineseCharactersForLegacyMigration(_ text: String) -> Bool {
        containsChineseScalars(text)
    }

    static func hasPendingOfflineLexiconEnrichment(
        entries: [VocabEntry],
        lookupHistory: [LookupHistoryRecord]
    ) -> Bool {
        if entries.contains(where: { entry in
            shouldAttemptOfflineLexiconEnrichment(
                term: entry.term,
                kind: entry.kind,
                meaningGroups: entry.meaningGroups,
                partOfSpeech: entry.partOfSpeech,
                englishDefinitions: entry.englishDefinitions,
                inflectionLines: entry.inflectionLines,
                referenceTags: entry.referenceTags
            )
        }) {
            return true
        }

        return lookupHistory.contains(where: { record in
            guard record.content.translationDirection != .chineseToEnglish else {
                return false
            }

            return shouldAttemptOfflineLexiconEnrichment(
                term: record.content.term,
                kind: record.content.kind,
                meaningGroups: record.content.meaningGroups,
                partOfSpeech: record.content.partOfSpeech,
                englishDefinitions: record.content.englishDefinitions,
                inflectionLines: record.content.inflectionLines,
                referenceTags: record.content.referenceTags
            )
        })
    }

    static func enrichedLoadedOfflineData(
        entries: [VocabEntry],
        lookupHistory: [LookupHistoryRecord],
        manifest: OfflineResourceManifest
    ) -> (entries: [VocabEntry], lookupHistory: [LookupHistoryRecord]) {
        var cache: [String: OfflineLexiconCore?] = [:]

        let enrichedEntries = entries.map { entry in
            enrichedLoadedEntry(entry, manifest: manifest, cache: &cache)
        }

        let enrichedLookupHistory = lookupHistory.map { record in
            enrichedLoadedLookupHistoryRecord(record, manifest: manifest, cache: &cache)
        }

        return (enrichedEntries, enrichedLookupHistory)
    }

    static func enrichedLoadedEntry(
        _ entry: VocabEntry,
        manifest: OfflineResourceManifest,
        cache: inout [String: OfflineLexiconCore?]
    ) -> VocabEntry {
        guard shouldAttemptOfflineLexiconEnrichment(
            term: entry.term,
            kind: entry.kind,
            meaningGroups: entry.meaningGroups,
            partOfSpeech: entry.partOfSpeech,
            englishDefinitions: entry.englishDefinitions,
            inflectionLines: entry.inflectionLines,
            referenceTags: entry.referenceTags
        ) else {
            return entry
        }

        guard let core = cachedOfflineLexiconPreview(
            term: entry.term,
            kind: entry.kind,
            manifest: manifest,
            cache: &cache
        ) else {
            return entry
        }

        guard shouldApplyOfflineLexiconEnrichment(
            currentMeaningGroups: entry.meaningGroups,
            currentPartOfSpeech: entry.partOfSpeech,
            currentEnglishDefinitions: entry.englishDefinitions,
            currentInflectionLines: entry.inflectionLines,
            currentReferenceTags: entry.referenceTags,
            core: core
        ) else {
            return entry
        }

        var enrichedEntry = entry
        let selectedMeanings = enrichedEntry.selectedMeanings
        let fallbackMeanings = MeaningGroup.flattenedMeanings(
            from: core.meaningGroups,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        let enrichedMeaningGroups = MeaningGroup.normalized(
            core.meaningGroups,
            fallbackPartOfSpeech: core.partOfSpeech,
            fallbackMeanings: fallbackMeanings,
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        let enrichedMeaningChoices = MeaningGroup.flattenedMeanings(
            from: enrichedMeaningGroups,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )

        guard !enrichedMeaningChoices.isEmpty else {
            return entry
        }

        enrichedEntry.meaningGroups = enrichedMeaningGroups
        enrichedEntry.partOfSpeech = MeaningGroup.primaryPartOfSpeech(
            from: enrichedMeaningGroups,
            fallback: core.partOfSpeech
        )
        enrichedEntry.meaningChoices = enrichedMeaningChoices
        enrichedEntry.selectedMeaningIndexes = remappedSelectionIndexes(
            selectedMeanings,
            in: enrichedMeaningChoices
        )
        enrichedEntry.englishDefinitions = core.englishDefinitions
        enrichedEntry.englishSynonyms = core.englishSynonyms
        enrichedEntry.inflectionLines = core.inflectionLines
        enrichedEntry.referenceTags = core.referenceTags
        enrichedEntry.sanitizeSelections()
        return enrichedEntry
    }

    static func enrichedLoadedLookupHistoryRecord(
        _ record: LookupHistoryRecord,
        manifest: OfflineResourceManifest,
        cache: inout [String: OfflineLexiconCore?]
    ) -> LookupHistoryRecord {
        guard record.content.translationDirection != .chineseToEnglish else {
            return record
        }

        guard shouldAttemptOfflineLexiconEnrichment(
            term: record.content.term,
            kind: record.content.kind,
            meaningGroups: record.content.meaningGroups,
            partOfSpeech: record.content.partOfSpeech,
            englishDefinitions: record.content.englishDefinitions,
            inflectionLines: record.content.inflectionLines,
            referenceTags: record.content.referenceTags
        ) else {
            return record
        }

        guard let core = cachedOfflineLexiconPreview(
            term: record.content.term,
            kind: record.content.kind,
            manifest: manifest,
            cache: &cache
        ) else {
            return record
        }

        guard shouldApplyOfflineLexiconEnrichment(
            currentMeaningGroups: record.content.meaningGroups,
            currentPartOfSpeech: record.content.partOfSpeech,
            currentEnglishDefinitions: record.content.englishDefinitions,
            currentInflectionLines: record.content.inflectionLines,
            currentReferenceTags: record.content.referenceTags,
            core: core
        ) else {
            return record
        }

        var enrichedRecord = record
        let fallbackMeanings = MeaningGroup.flattenedMeanings(
            from: core.meaningGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        enrichedRecord.content.meaningGroups = MeaningGroup.normalized(
            core.meaningGroups,
            fallbackPartOfSpeech: core.partOfSpeech,
            fallbackMeanings: fallbackMeanings,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        enrichedRecord.content.partOfSpeech = MeaningGroup.primaryPartOfSpeech(
            from: enrichedRecord.content.meaningGroups,
            fallback: core.partOfSpeech
        )
        enrichedRecord.content.meanings = MeaningGroup.flattenedMeanings(
            from: enrichedRecord.content.meaningGroups,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        enrichedRecord.content.englishDefinitions = core.englishDefinitions
        enrichedRecord.content.englishSynonyms = core.englishSynonyms
        enrichedRecord.content.inflectionLines = core.inflectionLines
        enrichedRecord.content.referenceTags = core.referenceTags
        return enrichedRecord
    }

    static func shouldAttemptOfflineLexiconEnrichment(
        term: String,
        kind: EntryKind,
        meaningGroups: [MeaningGroup],
        partOfSpeech: String,
        englishDefinitions: [String],
        inflectionLines: [String],
        referenceTags: [String]
    ) -> Bool {
        guard kind == .word else {
            return false
        }

        guard isLikelyEnglishLexiconTerm(term) else {
            return false
        }

        let normalizedGroups = MeaningGroup.normalized(
            meaningGroups,
            fallbackPartOfSpeech: partOfSpeech,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        let distinctPartsOfSpeech = Set(normalizedGroups.map {
            normalizedPartOfSpeechKey($0.partOfSpeech)
        })

        return distinctPartsOfSpeech.count <= 1
            || englishDefinitions.isEmpty
            || inflectionLines.isEmpty
            || referenceTags.isEmpty
    }

    static func shouldApplyOfflineLexiconEnrichment(
        currentMeaningGroups: [MeaningGroup],
        currentPartOfSpeech: String,
        currentEnglishDefinitions: [String],
        currentInflectionLines: [String],
        currentReferenceTags: [String],
        core: OfflineLexiconCore
    ) -> Bool {
        let currentGroups = MeaningGroup.normalized(
            currentMeaningGroups,
            fallbackPartOfSpeech: currentPartOfSpeech,
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )
        let enrichedGroups = MeaningGroup.normalized(
            core.meaningGroups,
            fallbackPartOfSpeech: core.partOfSpeech,
            fallbackMeanings: MeaningGroup.flattenedMeanings(
                from: core.meaningGroups,
                maxCount: EntryCandidateDefaults.meaningChoiceCount
            ),
            maxMeanings: EntryCandidateDefaults.meaningChoiceCount
        )

        guard !enrichedGroups.isEmpty else {
            return false
        }

        let currentPOSCount = Set(currentGroups.map { normalizedPartOfSpeechKey($0.partOfSpeech) }).count
        let enrichedPOSCount = Set(enrichedGroups.map { normalizedPartOfSpeechKey($0.partOfSpeech) }).count

        if enrichedPOSCount > currentPOSCount {
            return true
        }

        if MeaningGroup.primaryPartOfSpeech(from: enrichedGroups, fallback: core.partOfSpeech)
            != MeaningGroup.primaryPartOfSpeech(from: currentGroups, fallback: currentPartOfSpeech) {
            return true
        }

        if currentEnglishDefinitions.isEmpty && !core.englishDefinitions.isEmpty {
            return true
        }

        if currentInflectionLines.isEmpty && !core.inflectionLines.isEmpty {
            return true
        }

        if currentReferenceTags.isEmpty && !core.referenceTags.isEmpty {
            return true
        }

        return false
    }

    static func cachedOfflineLexiconPreview(
        term: String,
        kind: EntryKind,
        manifest: OfflineResourceManifest,
        cache: inout [String: OfflineLexiconCore?]
    ) -> OfflineLexiconCore? {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(kind.rawValue)::\(cleanedTerm.lowercased())"

        if let cached = cache[cacheKey] {
            return cached
        }

        let preview = OfflineLexiconService.shared.lookupEnglishQuickPreview(
            term: cleanedTerm,
            kind: kind,
            manifest: manifest
        )
        cache[cacheKey] = preview
        return preview
    }

    static func remappedSelectionIndexes(_ selectedMeanings: [String], in choices: [String]) -> [Int] {
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

    static func captureMeaningCandidates(
        meaningGroups: [MeaningGroup],
        fallbackPartOfSpeech: String,
        fallbackMeanings: [String],
        fallbackSelectedIndexes: [Int]
    ) -> [CaptureMeaningCandidate] {
        let groups = meaningGroups.isEmpty
            ? MeaningGroup.normalized(
                [],
                fallbackPartOfSpeech: fallbackPartOfSpeech,
                fallbackMeanings: fallbackMeanings,
                maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
            )
            : MeaningGroup.normalizedMergedWithFallback(
                meaningGroups,
                fallbackPartOfSpeech: fallbackPartOfSpeech,
                fallbackMeanings: fallbackMeanings,
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
        let selectedMeanings: [String] = fallbackSelectedIndexes.compactMap { index -> String? in
            guard fallbackMeanings.indices.contains(index) else {
                return nil
            }
            return fallbackMeanings[index]
        }

        return flattened.enumerated().map { index, meaning in
            CaptureMeaningCandidate(
                partOfSpeech: labels.indices.contains(index) ? labels[index] : fallbackPartOfSpeech,
                meaning: meaning,
                isSelected: selectedMeanings.contains(where: {
                    $0.caseInsensitiveCompare(meaning) == .orderedSame
                })
            )
        }
    }

    static func meaningGroups(
        from candidates: [CaptureMeaningCandidate],
        fallbackPartOfSpeech: String
    ) -> [MeaningGroup] {
        let groups = candidates.compactMap { candidate -> MeaningGroup? in
            let meaning = candidate.trimmedMeaning
            guard !meaning.isEmpty else {
                return nil
            }

            return MeaningGroup(
                partOfSpeech: candidate.trimmedPartOfSpeech.isEmpty ? fallbackPartOfSpeech : candidate.trimmedPartOfSpeech,
                meanings: [meaning]
            )
        }

        return MeaningGroup.normalizedMergedWithFallback(
            groups,
            fallbackPartOfSpeech: fallbackPartOfSpeech,
            fallbackMeanings: candidates.map(\.meaning),
            maxMeanings: EntryCandidateDefaults.editableMeaningChoiceCount
        )
    }

    static func mergedCaptureMeaningCandidates(
        current: [CaptureMeaningCandidate],
        existingGroups: [MeaningGroup],
        existingSelectedMeanings: [String],
        fallbackPartOfSpeech: String
    ) -> [CaptureMeaningCandidate] {
        let existingCandidates = captureMeaningCandidates(
            meaningGroups: existingGroups,
            fallbackPartOfSpeech: fallbackPartOfSpeech,
            fallbackMeanings: MeaningGroup.flattenedMeanings(
                from: existingGroups,
                maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
            ),
            fallbackSelectedIndexes: []
        ).map { candidate in
            var updated = candidate
            updated.isSelected = existingSelectedMeanings.contains(where: {
                $0.caseInsensitiveCompare(candidate.meaning) == .orderedSame
            })
            return updated
        }

        var merged: [CaptureMeaningCandidate] = []

        for candidate in current + existingCandidates {
            let key = "\(candidate.trimmedPartOfSpeech.lowercased())::\(candidate.trimmedMeaning.lowercased())"
            guard !candidate.trimmedMeaning.isEmpty else {
                continue
            }

            if let existingIndex = merged.firstIndex(where: {
                "\($0.trimmedPartOfSpeech.lowercased())::\($0.trimmedMeaning.lowercased())" == key
            }) {
                merged[existingIndex].isSelected = merged[existingIndex].isSelected || candidate.isSelected
                continue
            }

            merged.append(candidate)
            if merged.count >= EntryCandidateDefaults.editableMeaningChoiceCount {
                break
            }
        }

        if merged.isEmpty == false && merged.contains(where: \.isSelected) == false {
            merged[0].isSelected = true
        }

        return merged
    }

    static func isLikelyEnglishLexiconTerm(_ term: String) -> Bool {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else {
            return false
        }

        return cleanedTerm.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar == UnicodeScalar("'")
                || scalar == UnicodeScalar("-")
        }
    }

    static func normalizedPartOfSpeechKey(_ partOfSpeech: String) -> String {
        partOfSpeech
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizedChoiceEntries(_ choices: [String], maxCount: Int) -> [String] {
        Array(
            choices
                .flatMap(expandedStoredMeaningTexts(from:))
                .filter { !$0.isEmpty }
                .uniqued()
                .prefix(maxCount)
        )
    }

    static func mergedEntryMeaningChoices(
        incomingChoices: [String],
        existingChoices: [String] = []
    ) -> [String] {
        let normalizedIncoming = normalizedChoiceEntries(
            incomingChoices,
            maxCount: EntryCandidateDefaults.meaningChoiceCount
        )
        let normalizedExisting = normalizedChoiceEntries(
            existingChoices,
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
        let extraExistingCount = max(
            0,
            normalizedExisting.count - EntryCandidateDefaults.meaningChoiceCount
        )

        guard extraExistingCount > 0 else {
            return normalizedChoiceEntries(
                normalizedIncoming,
                maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
            )
        }

        let incomingKeys = Set(normalizedIncoming.map(normalizedStoredMeaningKey(_:)))
        let preservedExistingExtras = normalizedExisting.filter { choice in
            incomingKeys.contains(normalizedStoredMeaningKey(choice)) == false
        }

        return normalizedChoiceEntries(
            normalizedIncoming + Array(preservedExistingExtras.prefix(extraExistingCount)),
            maxCount: EntryCandidateDefaults.editableMeaningChoiceCount
        )
    }

    static func normalizedStoredMeaningKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizedLoadedMeaningGroups(
        kind: EntryKind,
        partOfSpeech: String,
        meaningGroups: [MeaningGroup],
        meanings: [String],
        maxMeanings: Int = EntryCandidateDefaults.meaningChoiceCount
    ) -> [MeaningGroup] {
        let fallbackPartOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? {
                switch kind {
                case .phrase:
                    return "短语"
                case .sentence:
                    return "句子"
                case .word:
                    return "单词"
                }
            }()
            : partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanedMeanings = meanings
            .flatMap(expandedStoredMeaningTexts(from:))
            .filter { !$0.isEmpty }
        let flattenedGroupMeanings = meaningGroups
            .flatMap(\.meanings)
            .flatMap(expandedStoredMeaningTexts(from:))
            .filter { !$0.isEmpty }
        let mergedMeanings = Array((flattenedGroupMeanings + cleanedMeanings).uniqued())
        let containsVerbInflection = mergedMeanings.contains(where: isVerbInflectionMeaning(_:))

        if containsVerbInflection, meaningGroups.count <= 1 {
            let inferredGroups = mergedMeanings.map { meaning in
                MeaningGroup(
                    partOfSpeech: repairedStoredMeaningPartOfSpeech(
                        for: meaning,
                        fallbackPartOfSpeech: fallbackPartOfSpeech,
                        containsVerbInflection: containsVerbInflection
                    ),
                    meanings: [meaning]
                )
            }

            return MeaningGroup.normalized(
                inferredGroups,
                fallbackPartOfSpeech: fallbackPartOfSpeech,
                fallbackMeanings: mergedMeanings,
                maxMeanings: maxMeanings
            )
        }

        let cleanedGroups = meaningGroups.map { group in
            MeaningGroup(
                partOfSpeech: group.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackPartOfSpeech : group.partOfSpeech,
                meanings: group.meanings.flatMap(expandedStoredMeaningTexts(from:)).filter { !$0.isEmpty }
            )
        }

        return MeaningGroup.normalizedMergedWithFallback(
            cleanedGroups,
            fallbackPartOfSpeech: fallbackPartOfSpeech,
            fallbackMeanings: mergedMeanings,
            maxMeanings: maxMeanings
        )
    }

    static func sanitizedStoredMeaningText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let markerOnly = trimmed
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let junkMarkers: Set<String> = [
            "pa", "pp", "vt", "vi", "v", "n", "a", "adj", "adv", "ad", "prep", "pron", "conj", "aux"
        ]

        if junkMarkers.contains(markerOnly) {
            return ""
        }

        if containsChineseCharactersForStoredMeaning(trimmed) == false,
           isVerbInflectionMeaning(trimmed) == false {
            return ""
        }

        return trimmed
    }

    static func expandedStoredMeaningTexts(from text: String) -> [String] {
        let cleaned = sanitizedStoredMeaningText(text)
        guard !cleaned.isEmpty else {
            return []
        }

        if containsChineseCharactersForStoredMeaning(cleaned),
           cleaned.contains(where: \.isWhitespace),
           cleaned.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.value < 128 }) == false {
            let expanded = cleaned
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if expanded.count > 1 {
                return expanded
            }
        }

        return [cleaned]
    }

    static func isVerbInflectionMeaning(_ meaning: String) -> Bool {
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        return trimmed.contains("过去式")
            || trimmed.contains("过去分词")
            || trimmed.contains("现在分词")
            || trimmed.contains("第三人称单数")
            || trimmed.contains("动名词")
            || trimmed.contains("原形")
            || trimmed.contains("不定式")
    }

    static func repairedStoredMeaningPartOfSpeech(
        for meaning: String,
        fallbackPartOfSpeech: String,
        containsVerbInflection: Bool
    ) -> String {
        if isVerbInflectionMeaning(meaning) {
            return "动词"
        }

        if containsVerbInflection,
           fallbackPartOfSpeech == "名词",
           meaning.hasSuffix("的") {
            return "形容词"
        }

        return fallbackPartOfSpeech
    }

    static func containsChineseCharactersForStoredMeaning(_ text: String) -> Bool {
        containsChineseScalars(text)
    }

    static func cleanedGeneratedExamples(
        _ examples: [String],
        term: String,
        sourceContext: String
    ) -> [String] {
        let cleanedExamples = normalizedChoiceEntries(
            examples.filter { example in
                isFallbackGeneratedExample(example, term: term) == false
            },
            maxCount: EntryCandidateDefaults.exampleChoiceCount
        )

        if !cleanedExamples.isEmpty {
            return cleanedExamples
        }

        return fallbackGeneratedExamples(term: term, sourceContext: sourceContext)
    }

    static func isFallbackGeneratedExample(_ example: String, term: String) -> Bool {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedTerm.isEmpty else {
            return false
        }

        let normalizedExample = example
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedExample == "i wrote down \(cleanedTerm) so i could review it later."
            || normalizedExample == "seeing \(cleanedTerm) in a sentence makes it easier to remember."
            || normalizedExample == "\(cleanedTerm) showed up again in my notes today."
    }

    static func fallbackGeneratedExamples(term _: String, sourceContext: String) -> [String] {
        let cleanedContext = sourceContext.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedContext.isEmpty else {
            return []
        }

        return normalizedChoiceEntries([cleanedContext], maxCount: EntryCandidateDefaults.exampleChoiceCount)
    }
}
