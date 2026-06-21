import AppKit
import SwiftUI

@main
struct SparrowWordApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("SparrowWord", id: "main") {
            ContentView(appState: appState)
                .frame(minWidth: 820, minHeight: 620)
        }

        Window("SparrowWord Capture", id: "capture") {
            CapturePanelView(appState: appState)
                .frame(width: 620, height: 860)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("SparrowWord", systemImage: "character.book.closed") {
            MenuBarLookupPanel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLookupPanel: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var kind: EntryKind = .word
    @State private var query = ""
    @State private var hasSearched = false
    @State private var isCapturing = false

    private var displayLanguage: AppDisplayLanguage {
        appState.displayLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(displayLanguage.text("快速录入", "Quick Capture"))
                    .font(.title2.weight(.semibold))

                Spacer()

                Button(displayLanguage.text("打开主窗口", "Open Main App")) {
                    openWindow(id: "main")
                }
                .buttonStyle(.borderless)
            }

            Picker(displayLanguage.text("类型", "Type"), selection: $kind) {
                Text("单词".localized(in: displayLanguage)).tag(EntryKind.word)
                Text("词组".localized(in: displayLanguage)).tag(EntryKind.phrase)
                Text("句子".localized(in: displayLanguage)).tag(EntryKind.sentence)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button {
                    captureFromScreen()
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .buttonStyle(.bordered)
                .help(displayLanguage.text("截图识别文字后直接查词", "Capture text from the screen and look it up directly"))
                .disabled(isCapturing || appState.isLookingUp)

                TextField(placeholder, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(appState.activeLookupCorrection == nil ? Color.primary : Color.red)
                    .onSubmit {
                        submitLookup()
                    }

                Button(displayLanguage.text("查词", "Lookup")) {
                    submitLookup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCapturing)
            }

            if isCapturing {
                statusRow(displayLanguage.text("请拖动截取要识别的词或句子…", "Drag to capture the word or sentence you want to recognize…"), showsProgress: true)
            } else if hasSearched, appState.isLookingUp {
                statusRow(displayLanguage.text("正在整理这次查词结果…", "Finalizing this lookup result…"), showsProgress: true)
            } else {
                Text(appState.statusMessage.localized(in: displayLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            ScrollView {
                menuBody
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 260, maxHeight: 360)

            Divider()

            HStack {
                Button(displayLanguage.text("快速录入", "Quick Capture")) {
                    openWindow(id: "capture")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(displayLanguage.text("退出", "Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 430)
    }

    @ViewBuilder
    private var menuBody: some View {
        if !hasSearched {
            Text(displayLanguage.text("直接输入单词、词组或句子，或者点左侧按钮截图识词。默认先按单词处理。", "Type a word, phrase, or sentence directly, or capture text from the screen. Word mode is used by default."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            switch appState.lookupViewState {
            case .idle:
                Text("还没有可显示的查词结果。".localized(in: displayLanguage))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            case .loading(_, let previewRecord, let statusMessage):
                if let previewRecord {
                    CompactLookupCard(record: previewRecord, footerMessage: statusMessage, isLoading: true)
                } else {
                    statusRow(statusMessage.localized(in: displayLanguage), showsProgress: true)
                }
            case .candidateSelection(_, _, let candidates):
                VStack(alignment: .leading, spacing: 10) {
                    Text("英文候选".localized(in: displayLanguage))
                        .font(.headline)

                    ForEach(candidates) { candidate in
                        Button {
                            kind = candidate.english.contains(" ") ? .phrase : .word
                            query = candidate.english
                            appState.startLookup(term: candidate.english, kind: kind)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.english)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(candidate.chinese)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .failure(let query, let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayLanguage.text("“\(query)” 查询失败", "“\(query)” lookup failed"))
                        .font(.headline)
                    Text(message.localized(in: displayLanguage))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            case .success(let recordID):
                if let record = appState.lookupRecord(id: recordID) {
                    CompactLookupCard(record: record, footerMessage: nil, isLoading: false)
                }
            }
        }
    }

    private var placeholder: String {
        switch kind {
        case .word:
            return displayLanguage.text("输入单词，或截图识词", "Type a word, or capture one from the screen")
        case .phrase:
            return displayLanguage.text("输入词组，或截图识别短语", "Type a phrase, or capture one from the screen")
        case .sentence:
            return displayLanguage.text("输入句子，或截图识句", "Type a sentence, or capture one from the screen")
        }
    }

    @ViewBuilder
    private func statusRow(_ text: String, showsProgress: Bool) -> some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func submitLookup() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        hasSearched = true
        appState.startLookup(term: trimmedQuery, kind: kind)
        query = appState.lookupDraft.term
    }

    private func captureFromScreen() {
        isCapturing = true

        Task {
            do {
                let recognizedText = try await appState.captureTextFromScreen()
                await MainActor.run {
                    query = recognizedText
                    hasSearched = true
                    isCapturing = false
                    appState.startLookup(term: recognizedText, kind: kind)
                }
            } catch {
                await MainActor.run {
                    isCapturing = false
                    appState.statusMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct CompactLookupCard: View {
    let record: LookupHistoryRecord
    let footerMessage: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.content.term)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(record.correction == nil ? Color.primary : Color.red)

                Spacer()

                if let partOfSpeech = DisplayFormatting.abbreviatedPartOfSpeech(
                    record.content.partOfSpeech,
                    kind: record.content.kind
                ) {
                    Text(partOfSpeech)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !record.content.pronunciation.isEmpty {
                Text(record.content.pronunciation)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            if record.originalQuery != record.content.term {
                Text("原始查询：\(record.originalQuery)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let correction = record.correction {
                Text("自动纠正：\(correction.originalTerm) -> \(correction.correctedTerm)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(
                    DisplayFormatting.meaningLines(
                        meaningGroups: record.content.meaningGroups,
                        kind: record.content.kind,
                        maxLineLength: 18
                    ),
                    id: \.self
                ) { line in
                    Text(line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if let example = record.content.examples.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.english)
                    Text(example.chinese)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if isLoading, let footerMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(footerMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
