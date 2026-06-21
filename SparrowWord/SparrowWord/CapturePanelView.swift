import SwiftUI

struct CapturePanelView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    private var displayLanguage: AppDisplayLanguage {
        appState.displayLanguage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SparrowWord Capture")
                            .font(.title3.weight(.semibold))
                        Text("这里现在可以直接保存 Quick Capture 草稿，或者正式写入词库。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button("新建") {
                        appState.startFreshCaptureDraft()
                    }
                    .buttonStyle(.bordered)
                }

                Picker("录入类型".localized(in: displayLanguage), selection: $appState.captureDraft.kind) {
                    ForEach(EntryKind.allCases) { kind in
                        Text(kind.title.localized(in: displayLanguage)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField(
                    appState.captureDraft.kind.fieldPlaceholder.localized(in: displayLanguage),
                    text: $appState.captureDraft.term
                )
                .textFieldStyle(.roundedBorder)
                .font(.title3.weight(.semibold))

                if let currentCaptureLibraryEntry = appState.currentCaptureLibraryEntry {
                    Label(
                        "\"\(currentCaptureLibraryEntry.term)\" 已在词库中，再保存会更新这个正式词条。",
                        systemImage: "books.vertical"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Spacer()

                    Button("保存为草稿".localized(in: displayLanguage)) {
                        _ = appState.saveCaptureAsDraft()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appState.captureDraft.isValid)

                    Button(
                        appState.currentCaptureLibraryEntry == nil
                            ? "保存到词库".localized(in: displayLanguage)
                            : "更新词库词条".localized(in: displayLanguage)
                    ) {
                        if appState.saveCaptureToLibrary() {
                            dismissWindow(id: "capture")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.captureDraft.isValid)
                }

                HStack(spacing: 12) {
                    Picker("初始熟练度".localized(in: displayLanguage), selection: $appState.captureDraft.proficiency) {
                        ForEach(ProficiencyLevel.allCases) { level in
                            Text(level.title.localized(in: displayLanguage)).tag(level)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button("填入建议".localized(in: displayLanguage)) {
                        appState.fillCaptureDraftSuggestions()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appState.captureDraft.isValid)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("原句".localized(in: displayLanguage))
                        .font(.headline)
                    adaptiveMultilineField(
                        placeholder: "原句".localized(in: displayLanguage),
                        text: $appState.captureDraft.sourceContext
                    )
                }

                CaptureMeaningCandidatesSection(
                    title: "中文释义候选".localized(in: displayLanguage),
                    candidates: $appState.captureDraft.meaningCandidates,
                    entryKind: appState.captureDraft.kind,
                    language: displayLanguage
                )

                EditableChoicesSection(
                    title: "例句候选".localized(in: displayLanguage),
                    entries: $appState.captureDraft.exampleChoices,
                    selectedIndexes: $appState.captureDraft.selectedExampleIndexes,
                    showsValidationError: false,
                    maxEntryCount: EntryCandidateDefaults.exampleChoiceCount,
                    language: displayLanguage,
                    alwaysShowsCustomDraftField: true,
                    customDraftPlaceholder: displayLanguage.text("（自定义例句）", "(Custom example)")
                )

                inlineLabeledField(
                    title: "备注".localized(in: displayLanguage),
                    placeholder: "备注".localized(in: displayLanguage),
                    text: $appState.captureDraft.notes
                )

                Text(appState.statusMessage.localized(in: displayLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
        .background(FloatingWindowConfigurator())
        .onAppear {
            appState.scheduleAutomaticCaptureSuggestions()
        }
        .onChange(of: appState.captureDraft.term) { _, _ in
            appState.scheduleAutomaticCaptureSuggestions()
        }
        .onChange(of: appState.captureDraft.kind) { _, _ in
            appState.scheduleAutomaticCaptureSuggestions()
        }
    }

    @ViewBuilder
    private func adaptiveMultilineField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(1...2)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func inlineLabeledField(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.headline)
                .frame(width: 56, alignment: .leading)

            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
    }
}

struct CaptureMeaningCandidatesSection: View {
    let title: String
    @Binding var candidates: [CaptureMeaningCandidate]
    let entryKind: EntryKind
    let language: AppDisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Button {
                    appendCandidate()
                } label: {
                    Label("添加候选".localized(in: language), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(candidates.count >= EntryCandidateDefaults.editableMeaningChoiceCount)
            }

            ForEach($candidates) { $candidate in
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        candidate.isSelected.toggle()
                    } label: {
                        Image(systemName: candidate.isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(candidate.isSelected ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    TextField(
                        language.text("词性", "POS"),
                        text: partOfSpeechBinding(for: $candidate)
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.caption.weight(.semibold))
                    .frame(width: 24)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                    TextField(
                        language.text("释义", "Meaning"),
                        text: $candidate.meaning
                    )
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                candidate.isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                                lineWidth: 1
                            )
                    )

                    Button(role: .destructive) {
                        removeCandidate(candidate.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func appendCandidate() {
        guard candidates.count < EntryCandidateDefaults.editableMeaningChoiceCount else {
            return
        }

        candidates.append(
            CaptureMeaningCandidate(
                partOfSpeech: defaultPartOfSpeech,
                meaning: "",
                isSelected: candidates.isEmpty
            )
        )
    }

    private func removeCandidate(_ id: UUID) {
        candidates.removeAll { $0.id == id }
        if candidates.isEmpty == false && candidates.contains(where: \.isSelected) == false {
            candidates[0].isSelected = true
        }
    }

    private var defaultPartOfSpeech: String {
        switch entryKind {
        case .word:
            return "adj."
        case .phrase:
            return "phr."
        case .sentence:
            return ""
        }
    }

    private func partOfSpeechBinding(for candidate: Binding<CaptureMeaningCandidate>) -> Binding<String> {
        Binding(
            get: {
                let raw = candidate.wrappedValue.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
                return DisplayFormatting.abbreviatedPartOfSpeech(raw, kind: entryKind) ?? raw
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                candidate.wrappedValue.partOfSpeech =
                    DisplayFormatting.abbreviatedPartOfSpeech(trimmed, kind: entryKind) ?? trimmed
            }
        )
    }
}
