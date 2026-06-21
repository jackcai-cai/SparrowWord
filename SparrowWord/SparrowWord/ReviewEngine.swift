import Foundation

final class ReviewEngine {
    func nextCard(from entries: [VocabEntry], settings: AppSettings, sessionConfiguration: ReviewSessionConfiguration) -> ReviewCard? {
        let queue = orderedEntries(
            from: entries.filter { $0.status == .library },
            sort: .priority,
            excludeMastered: settings.excludeMasteredFromReview
        )

        guard let entry = queue.first else {
            return nil
        }

        return card(for: entry, within: queue, sessionConfiguration: sessionConfiguration)
    }

    func orderedEntries(
        from entries: [VocabEntry],
        sort: ReviewSortOption,
        excludeMastered: Bool
    ) -> [VocabEntry] {
        let filtered = entries.filter { entry in
            let trimmedTerm = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedMeaning = entry.preferredMeaning.trimmingCharacters(in: .whitespacesAndNewlines)

            return (!excludeMastered || entry.proficiency != .mastered)
                && !trimmedTerm.isEmpty
                && !trimmedMeaning.isEmpty
        }

        switch sort {
        case .priority:
            return filtered.sorted(by: comparePriorityEntries)
        case .newestFirst:
            return filtered.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }

                return comparePriorityEntries(lhs: lhs, rhs: rhs)
            }
        case .oldestFirst:
            return filtered.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }

                return comparePriorityEntries(lhs: lhs, rhs: rhs)
            }
        case .leastRecentlyReviewed:
            return filtered.sorted(by: compareLeastRecentlyReviewedEntries)
        case .alphabetical:
            return filtered.sorted { lhs, rhs in
                let left = lhs.term.localizedLowercase
                let right = rhs.term.localizedLowercase

                if left != right {
                    return left < right
                }

                return comparePriorityEntries(lhs: lhs, rhs: rhs)
            }
        }
    }

    func card(for entry: VocabEntry, within entries: [VocabEntry], sessionConfiguration: ReviewSessionConfiguration) -> ReviewCard {
        let mode = mode(for: entry, sessionConfiguration: sessionConfiguration)
        let answer: String
        let prompt: String
        let acceptedAnswers: [String]

        switch mode {
        case .meaningToTerm:
            answer = entry.term
            prompt = entry.preferredMeaning
            acceptedAnswers = [entry.term]
        case .termToMeaning:
            answer = entry.preferredMeaning
            prompt = entry.term
            acceptedAnswers = entry.selectedMeanings.isEmpty ? [entry.preferredMeaning] : entry.selectedMeanings
        case .multipleChoice:
            answer = entry.preferredMeaning
            prompt = entry.term
            acceptedAnswers = [entry.preferredMeaning]
        case .flashcardTermToMeaning:
            answer = entry.preferredMeaning
            prompt = entry.term
            acceptedAnswers = [entry.preferredMeaning]
        case .flashcardMeaningToTerm:
            answer = entry.term
            prompt = entry.preferredMeaning
            acceptedAnswers = [entry.term]
        }

        return ReviewCard(
            entryID: entry.id,
            mode: mode,
            prompt: prompt,
            promptTitle: mode.title,
            answer: answer,
            distractors: distractors(for: entry, mode: mode, from: entries),
            acceptedAnswers: acceptedAnswers.uniqued()
        )
    }

    private func comparePriorityEntries(lhs: VocabEntry, rhs: VocabEntry) -> Bool {
        if lhs.proficiency != rhs.proficiency {
            return lhs.proficiency < rhs.proficiency
        }

        switch (lhs.lastReviewedAt, rhs.lastReviewedAt) {
        case let (left?, right?):
            if left != right {
                return left < right
            }
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case (nil, nil):
            break
        }

        return lhs.createdAt < rhs.createdAt
    }

    private func compareLeastRecentlyReviewedEntries(lhs: VocabEntry, rhs: VocabEntry) -> Bool {
        switch (lhs.lastReviewedAt, rhs.lastReviewedAt) {
        case let (left?, right?):
            if left != right {
                return left < right
            }
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case (nil, nil):
            break
        }

        if lhs.proficiency != rhs.proficiency {
            return lhs.proficiency < rhs.proficiency
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.term.localizedLowercase < rhs.term.localizedLowercase
    }

    private func mode(for entry: VocabEntry, sessionConfiguration: ReviewSessionConfiguration) -> ReviewMode {
        switch selectedQuestionType(for: entry, sessionConfiguration: sessionConfiguration) {
        case .multipleChoice:
            return .multipleChoice
        case .fillIn:
            return .meaningToTerm
        case .flashcards:
            switch entry.proficiency {
            case .unknown, .shaky:
                return .flashcardTermToMeaning
            case .familiar, .comfortable, .mastered:
                return .flashcardMeaningToTerm
            }
        }
    }

    private func selectedQuestionType(
        for entry: VocabEntry,
        sessionConfiguration: ReviewSessionConfiguration
    ) -> ReviewQuestionType {
        let questionTypes = sessionConfiguration.orderedQuestionTypes

        guard questionTypes.isEmpty == false else {
            return .multipleChoice
        }

        guard questionTypes.count > 1 else {
            return questionTypes[0]
        }

        let seed = entry.id.uuidString.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult * 31 + Int(scalar.value)) % 9_973
        }

        let index = abs(seed + entry.reviewCount + entry.term.count) % questionTypes.count
        return questionTypes[index]
    }

    private func distractors(for entry: VocabEntry, mode: ReviewMode, from entries: [VocabEntry]) -> [String] {
        guard mode == .multipleChoice else {
            return []
        }

        let pool = entries
            .filter { $0.id != entry.id }
            .map(\.preferredMeaning)
            .filter { $0 != entry.preferredMeaning }

        let fallback = [
            "\"\(entry.term)\" 的情绪化表达",
            "\"\(entry.term)\" 的正式书面说法",
            "\"\(entry.term)\" 的延伸比喻义"
        ]

        let options = Array(([entry.preferredMeaning] + pool + fallback).uniqued().prefix(4)).shuffled()
        return options
    }
}
