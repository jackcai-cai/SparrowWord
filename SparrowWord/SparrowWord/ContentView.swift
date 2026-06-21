import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MarqueeSelectionBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct MarqueeViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

extension View {
    func marqueeSelectableFrame(id: UUID, coordinateSpaceName: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MarqueeSelectionBoundsPreferenceKey.self,
                    value: [id: proxy.frame(in: .named(coordinateSpaceName))]
                )
            }
        )
    }

    func marqueeViewportFrame(coordinateSpaceName: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MarqueeViewportFramePreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName))
                )
            }
        )
    }
}

struct MarqueeSelectionOverlay: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }
}

func marqueeSelectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
    )
}

final class ScrollViewResolverHostView: NSView {
    var onResolve: ((NSScrollView) -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        resolveIfPossible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveIfPossible()
    }

    override func layout() {
        super.layout()
        resolveIfPossible()
    }

    func resolveIfPossible() {
        if let scrollView = enclosingScrollView {
            onResolve?(scrollView)
            return
        }

        var current: NSView? = superview
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView ?? candidate.enclosingScrollView {
                onResolve?(scrollView)
                return
            }
            current = candidate.superview
        }
    }
}

struct ScrollViewResolver: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> ScrollViewResolverHostView {
        let view = ScrollViewResolverHostView(frame: .zero)
        view.onResolve = onResolve
        DispatchQueue.main.async {
            view.resolveIfPossible()
        }
        return view
    }

    func updateNSView(_ nsView: ScrollViewResolverHostView, context: Context) {
        nsView.onResolve = onResolve
        DispatchQueue.main.async {
            nsView.resolveIfPossible()
        }
    }
}

func marqueeAutoScrollVelocity(for point: CGPoint, within viewport: CGRect) -> CGFloat {
    guard viewport != .zero else {
        return 0
    }

    let edgeInset: CGFloat = 72
    let maxVelocity: CGFloat = 30

    if point.y >= viewport.maxY - edgeInset {
        let distance = min(edgeInset, point.y - (viewport.maxY - edgeInset))
        return min(maxVelocity, max(0, distance) * 0.7)
    }

    if point.y <= viewport.minY + edgeInset {
        let distance = min(edgeInset, (viewport.minY + edgeInset) - point.y)
        return -min(maxVelocity, max(0, distance) * 0.7)
    }

    return 0
}

@discardableResult
func marqueeScroll(_ scrollView: NSScrollView, verticalDelta: CGFloat) -> Bool {
    guard let documentView = scrollView.documentView else {
        return false
    }

    let contentView = scrollView.contentView
    var visibleRect = contentView.documentVisibleRect
    let maxY = max(0, documentView.bounds.height - visibleRect.height)
    let nextY = min(max(visibleRect.origin.y + verticalDelta, 0), maxY)

    guard abs(nextY - visibleRect.origin.y) > 0.5 else {
        return false
    }

    visibleRect.origin.y = nextY
    contentView.scroll(to: visibleRect.origin)
    scrollView.reflectScrolledClipView(contentView)
    return true
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var librarySearch = ""
    @State private var selectedLibraryLevel: ProficiencyLevel?
    @State private var historySearch = ""

    private var displayLanguage: AppDisplayLanguage {
        appState.displayLanguage
    }

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(spacing: 8) {
                    SidebarBrandHeader(language: displayLanguage)

                    ForEach(SidebarSection.allCases) { section in
                        SidebarRow(
                            section: section,
                            count: sectionCount(for: section),
                            isSelected: (appState.selectedSection ?? .lookup) == section,
                            language: displayLanguage
                        ) {
                            appState.selectedSection = section
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 250)
            .background {
                LiquidGlassPanelBackground(
                    cornerRadius: 24,
                    tint: Color.white.opacity(0.10),
                    gradientOpacity: 0.22,
                    shadowOpacity: 0.08
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .navigationTitle("SparrowWord")
        } detail: {
            Group {
                switch appState.selectedSection ?? .lookup {
                case .lookup:
                    LookupWorkspace(appState: appState)
                case .library:
                    LibraryWorkspace(
                        appState: appState,
                        librarySearch: $librarySearch,
                        selectedLibraryLevel: $selectedLibraryLevel,
                        entryBinding: entryBinding(for:)
                    )
                case .review:
                    ReviewWorkspace(appState: appState)
                case .history:
                    HistoryWorkspace(
                        appState: appState,
                        historySearch: $historySearch
                    )
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(displayLanguage.text("快速录入", "Quick Capture")) {
                        openContextAwareQuickCapture()
                        openWindow(id: "capture")
                    }

                    Button(displayLanguage.text("设置", "Settings")) {
                        appState.showingSettings = true
                    }
                }
            }
        }
        .sheet(isPresented: $appState.showingSettings) {
            SettingsView(appState: appState)
                .frame(width: 980, height: 780)
        }
    }

    private func sectionCount(for section: SidebarSection) -> Int {
        switch section {
        case .lookup:
            return 0
        case .library:
            return appState.libraryEntries.count
        case .review:
            return appState.entries.filter { $0.kind != .sentence }.count
        case .history:
            return appState.lookupHistory.count
        }
    }

    private func entryBinding(for entryID: UUID) -> Binding<VocabEntry>? {
        guard let index = appState.entries.firstIndex(where: { $0.id == entryID }) else {
            return nil
        }

        let fallbackEntry = appState.entries[index]

        return Binding(
            get: { appState.entries.first(where: { $0.id == entryID }) ?? fallbackEntry },
            set: { appState.replaceEntry($0) }
        )
    }

    private func openContextAwareQuickCapture() {
        switch appState.selectedSection {
        case .lookup:
            if case .success(let recordID) = appState.lookupViewState,
               let record = appState.lookupRecord(id: recordID) {
                let sourceContext = appState.lookupDraft.trimmedSourceContext.isEmpty
                    ? nil
                    : appState.lookupDraft.trimmedSourceContext
                appState.openLookupResultInQuickCapture(record.content, sourceContext: sourceContext)
            } else if appState.lookupDraft.isValid {
                let sourceContext = appState.lookupDraft.trimmedSourceContext.isEmpty
                    ? nil
                    : appState.lookupDraft.trimmedSourceContext
                appState.openLookupDraftInQuickCapture(
                    term: appState.lookupDraft.trimmedTerm,
                    kind: appState.lookupDraft.kind,
                    sourceContext: sourceContext
                )
            } else {
                appState.scheduleAutomaticCaptureSuggestions()
            }
        case .library:
            if let selectedLibraryID = appState.selectedLibraryID {
                appState.openLibraryEntryInQuickCapture(selectedLibraryID)
            }
        case .history:
            if let record = appState.selectedLookupHistoryRecord {
                appState.openLookupResultInQuickCapture(record.content, sourceContext: nil)
            }
        case .review, .none:
            break
        }
    }
}

private enum WorkspacePaneArrangement {
    case horizontal
    case vertical

    var usesVerticalSplit: Bool {
        self == .vertical
    }
}

private struct AdaptiveWorkspaceSplit<Primary: View, Secondary: View>: View {
    let arrangement: WorkspacePaneArrangement
    let primary: Primary
    let secondary: Secondary

    init(
        arrangement: WorkspacePaneArrangement,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.arrangement = arrangement
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        Group {
            if arrangement.usesVerticalSplit {
                VSplitView {
                    primary
                    secondary
                }
            } else {
                HSplitView {
                    primary
                    secondary
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func resolvedPaneArrangement(
    width: CGFloat,
    preference: WorkspacePaneLayoutPreference,
    automaticThreshold: CGFloat
) -> WorkspacePaneArrangement {
    switch preference {
    case .automatic:
        return width < automaticThreshold ? .vertical : .horizontal
    case .horizontal:
        return .horizontal
    case .vertical:
        return .vertical
    }
}

private struct LookupWorkspace: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var displayLanguage: AppDisplayLanguage {
        appState.displayLanguage
    }

    var body: some View {
        GeometryReader { proxy in
            let arrangement = resolvedPaneArrangement(
                width: proxy.size.width,
                preference: appState.settings.workspacePaneLayoutPreference,
                automaticThreshold: 880
            )
            let prefersCompactDetail = proxy.size.width < 1080

            Group {
                if arrangement == .vertical {
                    VStack(spacing: 0) {
                        lookupInputPane(arrangement: arrangement, prefersCompactDetail: true)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                            .overlay(Color.secondary.opacity(0.18))

                        lookupResultPane(arrangement: arrangement, prefersCompactDetail: true)
                    }
                } else {
                    AdaptiveWorkspaceSplit(arrangement: arrangement) {
                        lookupInputPane(arrangement: arrangement, prefersCompactDetail: prefersCompactDetail)
                    } secondary: {
                        lookupResultPane(arrangement: arrangement, prefersCompactDetail: prefersCompactDetail)
                    }
                }
            }
        }
    }

    private func lookupInputPane(
        arrangement: WorkspacePaneArrangement,
        prefersCompactDetail: Bool
    ) -> some View {
        let usesVerticalArrangement = arrangement == .vertical

        return VStack(alignment: .leading, spacing: arrangement == .vertical ? 12 : 16) {
            Text(displayLanguage.text("查词", "Lookup"))
                .font((usesVerticalArrangement ? Font.title2 : .largeTitle).weight(.semibold))

            Text("这里可以查单词、词组和句子。结果会先记录到历史；需要继续学习时，再显式送去 Quick Capture 或词库。中文单词/词组会先给英文候选，句子会走本地离线翻译。".localized(in: displayLanguage))
                .font(usesVerticalArrangement ? .footnote : .body)
                .foregroundStyle(.secondary)
                .lineLimit(usesVerticalArrangement ? 1 : nil)

            Picker(displayLanguage.text("类型", "Type"), selection: $appState.lookupDraft.kind) {
                Text("单词".localized(in: displayLanguage)).tag(EntryKind.word)
                Text("词组".localized(in: displayLanguage)).tag(EntryKind.phrase)
                Text("句子".localized(in: displayLanguage)).tag(EntryKind.sentence)
            }
            .pickerStyle(.segmented)
            .onChange(of: appState.lookupDraft.kind) { _, _ in
                appState.handleLookupKindChange()
            }

            HStack(spacing: 12) {
                TextField(lookupPlaceholder, text: lookupTermBinding)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(appState.activeLookupCorrection == nil ? Color.primary : Color.red)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                appState.activeLookupCorrection == nil ? Color.clear : Color.red.opacity(0.7),
                                lineWidth: 1
                            )
                    }
                    .onSubmit {
                        appState.lookupCurrentTerm()
                    }

                Button(displayLanguage.text("查词", "Lookup")) {
                    appState.lookupCurrentTerm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.lookupDraft.isValid)
            }

            if !usesVerticalArrangement && !appState.lookupSuggestions.isEmpty {
                LookupSuggestionsSection(
                    suggestions: appState.lookupSuggestions,
                    applySuggestion: appState.applyLookupSuggestion(_:),
                    language: displayLanguage
                )
            }

            if appState.lookupDraft.kind != .sentence {
                VStack(alignment: .leading, spacing: 8) {
                    Text("你遇到它时的原句 / 上下文".localized(in: displayLanguage))
                        .font(usesVerticalArrangement ? .subheadline.weight(.semibold) : .headline)

                    if arrangement == .vertical {
                        TextField(
                            "原句 / 上下文".localized(in: displayLanguage),
                            text: lookupSourceContextBinding,
                            axis: .vertical
                        )
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
                    } else {
                        TextEditor(text: lookupSourceContextBinding)
                            .frame(minHeight: 72, maxHeight: 96)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )

                        Text("查词时会把这段原句一起带进结果和后续的 Quick Capture / 词库保存；你在等待结果时补录，也会跟上这次查询。".localized(in: displayLanguage))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let correction = appState.activeLookupCorrection {
                Text("\(displayLanguage.text("已自动纠正：", "Auto-corrected: "))\(correction.originalTerm) -> \(correction.correctedTerm)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if appState.isLookingUp {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text((appState.activeLookupCorrection == nil ? "正在查词..." : "正在按纠正后的拼写继续查词...").localized(in: displayLanguage))
                        .foregroundStyle(.secondary)
                }
            }

            if appState.lookupDraft.kind == .sentence {
                SentenceEngineStatusCard(appState: appState, language: displayLanguage)
            }

            if !usesVerticalArrangement {
                Spacer()
            }
        }
        .padding(24)
        .frame(
            minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 250 : 300) : nil,
            idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 300 : 360) : nil,
            maxWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 420) : .infinity,
            maxHeight: arrangement == .vertical ? nil : .infinity,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func lookupResultPane(
        arrangement: WorkspacePaneArrangement,
        prefersCompactDetail: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: arrangement == .vertical ? 12 : 0) {
            if arrangement == .vertical, !appState.lookupSuggestions.isEmpty {
                LookupSuggestionsSection(
                    suggestions: appState.lookupSuggestions,
                    applySuggestion: appState.applyLookupSuggestion(_:),
                    language: displayLanguage
                )
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }

            switch appState.lookupViewState {
        case .idle:
            EmptyStateView(
                title: "还没有查词结果",
                subtitle: "输入英文、中文或句子先拿结果；要继续学习时，再显式送去 Quick Capture 或词库。",
                language: displayLanguage
            )
            .frame(
                minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 520) : nil,
                idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 440 : 560) : nil,
                maxWidth: .infinity,
                minHeight: arrangement == .vertical ? 260 : nil,
                maxHeight: .infinity,
                alignment: .center
            )
        case .loading(let query, let previewRecord, let statusMessage):
            if let previewRecord {
                    LookupDetailView(
                        record: previewRecord,
                        showsHistoryMeta: false,
                        onSelectReverseCandidate: nil,
                        loadingMessage: statusMessage,
                        isLoadingExamples: true,
                        showsReferenceTags: appState.settings.showLookupReferenceTags,
                        prefersCompactChrome: prefersCompactDetail,
                        showsStickyQuickCaptureAction: arrangement == .vertical,
                        language: displayLanguage,
                        voicePreference: appState.settings.pronunciationVoicePreference
                    )
                .frame(
                    minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 520) : nil,
                    idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 440 : 560) : nil,
                    maxWidth: .infinity,
                    minHeight: arrangement == .vertical ? 260 : nil,
                    maxHeight: .infinity,
                    alignment: .leading
                )
            } else {
                LookupStatusView(
                    title: "正在查询",
                    subtitle: "正在处理“\(query)”，请稍等一下。",
                    showsProgress: true,
                    language: displayLanguage
                )
                .frame(
                    minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 520) : nil,
                    idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 440 : 560) : nil,
                    maxWidth: .infinity,
                    minHeight: arrangement == .vertical ? 260 : nil,
                    maxHeight: .infinity,
                    alignment: .center
                )
            }
        case .candidateSelection(let query, let kind, let candidates):
            LookupDetailView(
                        record: LookupHistoryRecord.reverseLookupPreview(
                            query: query,
                            kind: kind,
                            candidates: candidates
                        ),
                        showsHistoryMeta: false,
                        onSelectReverseCandidate: appState.selectReverseLookupCandidate(_:),
                        onOpenReverseCandidateInQuickCapture: { candidate in
                            openReverseCandidateInQuickCapture(candidate)
                        },
                        showsReferenceTags: appState.settings.showLookupReferenceTags,
                        prefersCompactChrome: prefersCompactDetail,
                        showsStickyQuickCaptureAction: arrangement == .vertical,
                        language: displayLanguage,
                        voicePreference: appState.settings.pronunciationVoicePreference
                    )
            .frame(
                minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 520) : nil,
                idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 440 : 560) : nil,
                maxWidth: .infinity,
                minHeight: arrangement == .vertical ? 260 : nil,
                maxHeight: .infinity,
                alignment: .leading
            )
        case .failure(let query, let message):
            LookupStatusView(
                title: "这次查询失败了",
                subtitle: "“\(query)” 没有成功处理。\n\(message)",
                showsProgress: false,
                language: displayLanguage
            )
            .frame(
                minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 520) : nil,
                idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 440 : 560) : nil,
                maxWidth: .infinity,
                minHeight: arrangement == .vertical ? 260 : nil,
                maxHeight: .infinity,
                alignment: .center
            )
        case .success(let recordID):
            if let record = appState.lookupRecord(id: recordID) {
                LookupDetailView(
                        record: record,
                        showsHistoryMeta: false,
                        onSelectReverseCandidate: appState.selectReverseLookupCandidate(_:),
                        onOpenInQuickCapture: {
                            openLookupRecordInQuickCapture(record)
                        },
                        onQuickSaveToLibrary: {
                            _ = appState.saveLookupResultToLibrary(record.content, sourceContext: currentLookupSourceContext)
                        },
                        isInLibrary: isLookupRecordInLibrary(record),
                        showsReferenceTags: appState.settings.showLookupReferenceTags,
                        prefersCompactChrome: prefersCompactDetail,
                        showsStickyQuickCaptureAction: arrangement == .vertical,
                        language: displayLanguage,
                        voicePreference: appState.settings.pronunciationVoicePreference
                    )
                .frame(
                    minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 520) : nil,
                    idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 440 : 560) : nil,
                    maxWidth: .infinity,
                    minHeight: arrangement == .vertical ? 260 : nil,
                    maxHeight: .infinity,
                    alignment: .leading
                )
            } else {
                EmptyStateView(
                    title: "还没有查词结果",
                    subtitle: "输入英文、中文或句子先拿结果；要继续学习时，再显式送去 Quick Capture 或词库。",
                    language: displayLanguage
                    )
                .frame(
                    minWidth: arrangement == .horizontal ? (prefersCompactDetail ? 360 : 520) : nil,
                    idealWidth: arrangement == .horizontal ? (prefersCompactDetail ? 440 : 560) : nil,
                    maxWidth: .infinity,
                    minHeight: arrangement == .vertical ? 260 : nil,
                    maxHeight: .infinity,
                    alignment: .center
                )
            }
        }
        }
    }

    private var currentLookupSourceContext: String? {
        let trimmed = appState.lookupDraft.trimmedSourceContext
        return trimmed.isEmpty ? nil : trimmed
    }

    private var lookupPlaceholder: String {
        switch appState.lookupDraft.kind {
        case .word:
            return "输入要查的单词，也可以直接输中文反查英文".localized(in: displayLanguage)
        case .phrase:
            return "输入要查的词组，也可以直接输中文反查英文".localized(in: displayLanguage)
        case .sentence:
            return "输入英文或中文句子".localized(in: displayLanguage)
        }
    }

    private var lookupSourceContextBinding: Binding<String> {
        Binding(
            get: { appState.lookupDraft.sourceContext },
            set: { appState.updateLookupSourceContext($0) }
        )
    }

    private var lookupTermBinding: Binding<String> {
        Binding(
            get: { appState.lookupDraft.term },
            set: { appState.updateLookupTerm($0) }
        )
    }

    private func openLookupRecordInQuickCapture(_ record: LookupHistoryRecord) {
        appState.openLookupResultInQuickCapture(record.content, sourceContext: currentLookupSourceContext)
        openWindow(id: "capture")
    }

    private func openReverseCandidateInQuickCapture(_ candidate: ReverseLookupCandidate) {
        appState.openReverseCandidateInQuickCapture(candidate, sourceContext: currentLookupSourceContext)
        openWindow(id: "capture")
    }

    private func isLookupRecordInLibrary(_ record: LookupHistoryRecord) -> Bool {
        appState.libraryEntries.contains { entry in
            entry.kind == record.content.kind
                && entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(record.content.term.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
    }

}

private struct LibraryWorkspace: View {
    @ObservedObject var appState: AppState
    @Binding var librarySearch: String
    @Binding var selectedLibraryLevel: ProficiencyLevel?
    let entryBinding: (UUID) -> Binding<VocabEntry>?
    @State private var isSelecting = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var showingSortControls = false
    @State private var showingSaveArrangementPopover = false
    @State private var arrangementName = ""
    @State private var draggingEntryID: UUID?
    @State private var isDragSelecting = false
    @State private var ignoreNextTapAfterDrag = false
    @State private var marqueeStartPoint: CGPoint?
    @State private var marqueeCurrentPoint: CGPoint?
    @State private var marqueeBaseSelection: Set<UUID> = []
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var scrollViewportFrame: CGRect = .zero
    @State private var resolvedScrollView: NSScrollView?
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?

    private let selectionSpaceName = "LibraryMarqueeSelectionSpace"

    private var displayLanguage: AppDisplayLanguage {
        appState.displayLanguage
    }

    private var libraryCleanModeBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.isLibraryCleanMode },
            set: { newValue in
                appState.settings.isLibraryCleanMode = newValue
                appState.persistSettings()
                if newValue {
                    isSelecting = false
                    selectedEntryIDs.removeAll()
                    resetMarqueeSelection()
                }
            }
        )
    }

    var filteredEntries: [VocabEntry] {
        appState.entries(for: appState.selectedLibraryCollection).filter { entry in
            let matchesSearch = librarySearch.isEmpty
                || entry.term.localizedCaseInsensitiveContains(librarySearch)
                || entry.preferredMeaning.localizedCaseInsensitiveContains(librarySearch)

            let matchesLevel = selectedLibraryLevel == nil || entry.proficiency == selectedLibraryLevel

            return matchesSearch && matchesLevel
        }
    }

    private var activeMarqueeRect: CGRect? {
        guard let marqueeStartPoint, let marqueeCurrentPoint, isDragSelecting else {
            return nil
        }
        return marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
    }

    var body: some View {
        if appState.libraryEntries.isEmpty {
            EmptyStateView(
                title: "词库还没有条目",
                subtitle: "把词条正式保存进词库后，它们会在这里稳定积累。",
                language: displayLanguage
            )
        } else {
            GeometryReader { proxy in
                let arrangement = resolvedPaneArrangement(
                    width: proxy.size.width,
                    preference: appState.settings.workspacePaneLayoutPreference,
                    automaticThreshold: 920
                )

                AdaptiveWorkspaceSplit(arrangement: arrangement) {
                    VStack(alignment: .leading, spacing: 12) {
                    Picker("词组".localized(in: displayLanguage), selection: $appState.selectedLibraryCollectionID) {
                        ForEach(appState.libraryCollectionOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("搜索英文或中文释义".localized(in: displayLanguage), text: $librarySearch)

                    HStack(alignment: .center, spacing: 12) {
                        Picker("熟练度筛选".localized(in: displayLanguage), selection: $selectedLibraryLevel) {
                            Text("全部".localized(in: displayLanguage)).tag(Optional<ProficiencyLevel>.none)
                            ForEach(ProficiencyLevel.allCases) { level in
                                Text(level.title.localized(in: displayLanguage)).tag(Optional(level))
                            }
                        }
                        .pickerStyle(.menu)

                        if appState.selectedLibraryCollection.kind != .saved {
                            Button {
                                showingSortControls.toggle()
                            } label: {
                                Label("排序".localized(in: displayLanguage), systemImage: "arrow.up.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .popover(isPresented: $showingSortControls, arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("词库排序".localized(in: displayLanguage))
                                        .font(.title3.weight(.semibold))

                                    EntrySortRulesEditor(appState: appState)
                                }
                                .padding(16)
                                .frame(width: 360)
                            }
                        }

                        Button {
                            arrangementName = "排列 \(appState.settings.savedLibraryArrangements.count + 1)"
                            showingSaveArrangementPopover.toggle()
                        } label: {
                            Label("保存当前排列".localized(in: displayLanguage), systemImage: "bookmark")
                        }
                        .buttonStyle(.bordered)
                        .disabled(filteredEntries.isEmpty)
                        .popover(isPresented: $showingSaveArrangementPopover, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("保存当前排列".localized(in: displayLanguage))
                                    .font(.title3.weight(.semibold))

                                TextField("词组名称".localized(in: displayLanguage), text: $arrangementName)
                                    .textFieldStyle(.roundedBorder)

                                HStack {
                                    Spacer()
                                    Button("保存".localized(in: displayLanguage)) {
                                        appState.saveLibraryArrangement(
                                            name: arrangementName,
                                            entryIDs: filteredEntries.map(\.id)
                                        )
                                        showingSaveArrangementPopover = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(16)
                            .frame(width: 280)
                        }
                    }

                    HStack {
                        if !appState.settings.isLibraryCleanMode {
                            MultiSelectActionBar(
                                isSelecting: isSelecting,
                                selectedCount: selectedEntryIDs.count,
                                totalCount: filteredEntries.count,
                                onToggleSelecting: toggleSelectionMode,
                                onToggleSelectAll: toggleSelectAllEntries,
                                onDelete: deleteSelectedEntries,
                                language: displayLanguage
                            )
                        }

                        Spacer()

                        Toggle(isOn: libraryCleanModeBinding) {
                            Text("纯净视图".localized(in: displayLanguage))
                                .font(.subheadline.weight(.semibold))
                        }
                        .toggleStyle(.switch)
                        .frame(maxWidth: 180, alignment: .trailing)
                    }

                    if filteredEntries.isEmpty {
                        EmptyStateView(
                            title: appState.selectedLibraryCollection.kind == .favorites ? "收藏词组还是空的" : "这个词组里还没有词",
                            subtitle: appState.selectedLibraryCollection.kind == .favorites ? "先收藏一些词，它们才会出现在这里。" : "这个词组是固定排列，新词不会自动加入。",
                            language: displayLanguage
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredEntries) { entry in
                                    if appState.selectedLibraryCollection.arrangementID != nil && !isSelecting {
                                        EntryListButtonRow(
                                            entry: entry,
                                            isSelected: appState.selectedLibraryID == entry.id,
                                            language: displayLanguage
                                        ) {
                                            if ignoreNextTapAfterDrag {
                                                return
                                            }

                                            appState.selectedLibraryID = entry.id
                                        }
                                        .marqueeSelectableFrame(id: entry.id, coordinateSpaceName: selectionSpaceName)
                                        .onDrag {
                                            draggingEntryID = entry.id
                                            return NSItemProvider(object: entry.id.uuidString as NSString)
                                        }
                                        .onDrop(
                                            of: [.plainText],
                                            delegate: SavedArrangementEntryDropDelegate(
                                                targetEntryID: entry.id,
                                                draggingEntryID: $draggingEntryID,
                                                arrangementID: appState.selectedLibraryCollection.arrangementID,
                                                appState: appState
                                            )
                                        )
                                        .opacity(draggingEntryID == entry.id ? 0.7 : 1)
                                        .simultaneousGesture(
                                            LongPressGesture(minimumDuration: 0.35)
                                                .onEnded { _ in
                                                    activateDirectSelection(for: entry.id)
                                                }
                                        )
                                    } else {
                                        EntryListButtonRow(
                                            entry: entry,
                                            isSelected: isSelecting ? selectedEntryIDs.contains(entry.id) : appState.selectedLibraryID == entry.id,
                                            showsSelectionControl: isSelecting,
                                            isChecked: selectedEntryIDs.contains(entry.id),
                                            language: displayLanguage
                                        ) {
                                            if ignoreNextTapAfterDrag {
                                                return
                                            }

                                            if isSelecting {
                                                appState.selectedLibraryID = entry.id
                                                toggleSelection(for: entry.id)
                                            } else {
                                                appState.selectedLibraryID = entry.id
                                            }
                                        }
                                        .marqueeSelectableFrame(id: entry.id, coordinateSpaceName: selectionSpaceName)
                                        .simultaneousGesture(
                                            LongPressGesture(minimumDuration: 0.35)
                                                .onEnded { _ in
                                                    activateDirectSelection(for: entry.id)
                                                }
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .background(
                            ScrollViewResolver { scrollView in
                                if resolvedScrollView !== scrollView {
                                    resolvedScrollView = scrollView
                                }
                            }
                        )
                        .marqueeViewportFrame(coordinateSpaceName: selectionSpaceName)
                    }
                }
                .coordinateSpace(name: selectionSpaceName)
                .contentShape(Rectangle())
                .onPreferenceChange(MarqueeSelectionBoundsPreferenceKey.self) { frames in
                    rowFrames = frames
                    refreshMarqueeSelection()
                }
                .onPreferenceChange(MarqueeViewportFramePreferenceKey.self) { viewportFrame in
                    scrollViewportFrame = viewportFrame
                }
                .overlay(alignment: .topLeading) {
                    if let activeMarqueeRect {
                        MarqueeSelectionOverlay(rect: activeMarqueeRect)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(selectionSpaceName))
                        .onChanged { value in
                            updateMarqueeSelection(start: value.startLocation, current: value.location)
                        }
                        .onEnded { _ in
                            endMarqueeSelection()
                        }
                )
                .onChange(of: appState.selectedLibraryCollectionID) {
                    if let firstEntry = filteredEntries.first {
                        appState.selectedLibraryID = firstEntry.id
                    } else {
                        appState.selectedLibraryID = nil
                    }

                    selectedEntryIDs.removeAll()
                    isSelecting = false
                    resetMarqueeSelection()
                }
                .onChange(of: filteredEntries.map(\.id)) { _, entryIDs in
                    let validIDs = Set(entryIDs)
                    selectedEntryIDs.formIntersection(validIDs)
                    if isSelecting, validIDs.isEmpty {
                        isSelecting = false
                    }
                    if !isSelecting {
                        isDragSelecting = false
                    }

                    if let selectedLibraryID = appState.selectedLibraryID,
                       validIDs.contains(selectedLibraryID) == false {
                        appState.selectedLibraryID = filteredEntries.first?.id
                    }
                }
                .padding(16)
                .frame(
                    minWidth: arrangement == .horizontal ? 240 : nil,
                    idealWidth: arrangement == .horizontal ? 320 : nil,
                    maxWidth: arrangement == .horizontal ? 380 : .infinity,
                    minHeight: arrangement == .vertical ? 260 : nil,
                    idealHeight: arrangement == .vertical ? 340 : nil,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .onDisappear {
                    stopAutoScroll()
                }

                } secondary: {
                    if let selectedLibraryID = appState.selectedLibraryID, let binding = entryBinding(selectedLibraryID) {
                        Group {
                            if appState.settings.isLibraryCleanMode {
                                LibraryStudyView(
                                    entry: binding.wrappedValue,
                                    showsReferenceTags: appState.settings.showLookupReferenceTags,
                                    language: displayLanguage
                                )
                            } else {
                                EntryEditorView(
                                    entry: binding,
                                    isGenerating: appState.isGeneratingEntry(selectedLibraryID),
                                    duplicateCount: appState.duplicateEntries(for: selectedLibraryID).count,
                                    showsReferenceTags: appState.settings.showLookupReferenceTags,
                                    onToggleFavorite: { appState.toggleFavorite(for: selectedLibraryID) },
                                    onRegenerate: { appState.regenerateDraft(for: selectedLibraryID) },
                                    onPrimaryAction: nil,
                                    primaryActionTitle: nil,
                                    onSecondaryAction: { appState.deleteEntry(selectedLibraryID) },
                                    onMerge: { appState.mergeDuplicates(into: selectedLibraryID) },
                                    language: displayLanguage
                                )
                            }
                        }
                        .frame(
                            minWidth: arrangement == .horizontal ? 360 : nil,
                            idealWidth: arrangement == .horizontal ? 520 : nil,
                            maxWidth: .infinity,
                            minHeight: arrangement == .vertical ? 280 : nil,
                            maxHeight: .infinity,
                            alignment: .leading
                        )
                    } else {
                        EmptyStateView(
                            title: "选择一个词条",
                            subtitle: "词库里可以继续编辑旧词条、删除，或者把重复项合并。",
                            language: displayLanguage
                        )
                        .frame(
                            minWidth: arrangement == .horizontal ? 360 : nil,
                            idealWidth: arrangement == .horizontal ? 520 : nil,
                            maxWidth: .infinity,
                            minHeight: arrangement == .vertical ? 280 : nil,
                            maxHeight: .infinity,
                            alignment: .center
                        )
                    }
                }
            }
        }
    }

    private func toggleSelectionMode() {
        isSelecting.toggle()
        resetMarqueeSelection()
        if !isSelecting {
            selectedEntryIDs.removeAll()
        }
    }

    private func activateDirectSelection(for entryID: UUID) {
        ignoreNextTapAfterDrag = true
        appState.selectedLibraryID = entryID
        isSelecting = true
        selectedEntryIDs.insert(entryID)
        resetMarqueeSelection()
    }

    private func toggleSelection(for entryID: UUID) {
        if selectedEntryIDs.contains(entryID) {
            selectedEntryIDs.remove(entryID)
        } else {
            selectedEntryIDs.insert(entryID)
        }
    }

    private func toggleSelectAllEntries() {
        let allEntryIDs = Set(filteredEntries.map(\.id))
        if !allEntryIDs.isEmpty, selectedEntryIDs == allEntryIDs {
            selectedEntryIDs.removeAll()
        } else {
            selectedEntryIDs = allEntryIDs
        }
    }

    private func deleteSelectedEntries() {
        let entryIDs = selectedEntryIDs
        guard !entryIDs.isEmpty else {
            return
        }

        appState.deleteEntries(entryIDs)
        selectedEntryIDs.removeAll()
        isSelecting = false
        resetMarqueeSelection()
    }

    private func updateMarqueeSelection(start: CGPoint, current: CGPoint) {
        if appState.selectedLibraryCollection.arrangementID != nil && !isSelecting {
            return
        }

        if !isDragSelecting {
            marqueeBaseSelection = isSelecting ? selectedEntryIDs : []
            if !isSelecting {
                isSelecting = true
                selectedEntryIDs.removeAll()
                marqueeBaseSelection.removeAll()
            }
        }

        isDragSelecting = true
        ignoreNextTapAfterDrag = true
        marqueeStartPoint = start
        marqueeCurrentPoint = current
        refreshMarqueeSelection()
        updateAutoScroll(for: current)
    }

    private func endMarqueeSelection() {
        resetMarqueeSelection()
    }

    private func refreshMarqueeSelection() {
        guard isDragSelecting,
              let marqueeStartPoint,
              let marqueeCurrentPoint else {
            return
        }

        let rect = marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
        let intersectedIDs = Set<UUID>(filteredEntries.compactMap { entry in
            guard let frame = rowFrames[entry.id], frame.intersects(rect) else {
                return nil
            }
            return entry.id
        })

        selectedEntryIDs = marqueeBaseSelection.union(intersectedIDs)

        if let firstSelectedID = filteredEntries.first(where: { selectedEntryIDs.contains($0.id) })?.id {
            appState.selectedLibraryID = firstSelectedID
        }
    }

    private func updateAutoScroll(for point: CGPoint) {
        let velocity = marqueeAutoScrollVelocity(for: point, within: scrollViewportFrame)
        guard abs(velocity) > 0.1 else {
            stopAutoScroll()
            return
        }

        autoScrollVelocity = velocity
        guard autoScrollTask == nil else {
            return
        }

        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard isDragSelecting, let resolvedScrollView else {
                    break
                }

                _ = marqueeScroll(resolvedScrollView, verticalDelta: autoScrollVelocity)
                refreshMarqueeSelection()

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            autoScrollTask = nil
        }
    }

    private func stopAutoScroll() {
        autoScrollVelocity = 0
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func resetMarqueeSelection() {
        stopAutoScroll()
        isDragSelecting = false
        marqueeStartPoint = nil
        marqueeCurrentPoint = nil
        marqueeBaseSelection.removeAll()

        DispatchQueue.main.async {
            ignoreNextTapAfterDrag = false
        }
    }
}

private struct HistoryWorkspace: View {
    @ObservedObject var appState: AppState
    @Binding var historySearch: String
    @Environment(\.openWindow) private var openWindow
    @State private var isSelecting = false
    @State private var selectedHistoryIDs: Set<UUID> = []
    @State private var isDragSelecting = false
    @State private var ignoreNextTapAfterDrag = false
    @State private var marqueeStartPoint: CGPoint?
    @State private var marqueeCurrentPoint: CGPoint?
    @State private var marqueeBaseSelection: Set<UUID> = []
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var scrollViewportFrame: CGRect = .zero
    @State private var resolvedScrollView: NSScrollView?
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?

    private let selectionSpaceName = "HistoryMarqueeSelectionSpace"

    var filteredHistory: [LookupHistoryRecord] {
        appState.lookupHistory.filter { record in
            let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                return true
            }

            let meaningText = DisplayFormatting.meaningLines(
                meaningGroups: record.content.meaningGroups,
                kind: record.content.kind,
                maxLineLength: 60
            ).joined(separator: " ")
            let candidateText = record.reverseLookupCandidates
                .flatMap { [$0.english, $0.chinese, $0.pinyin] }
                .joined(separator: " ")

            return record.content.term.localizedCaseInsensitiveContains(query)
                || record.originalQuery.localizedCaseInsensitiveContains(query)
                || meaningText.localizedCaseInsensitiveContains(query)
                || record.content.examples.map(\.chinese).joined(separator: " ").localizedCaseInsensitiveContains(query)
                || (record.statusMessage?.localizedCaseInsensitiveContains(query) ?? false)
                || candidateText.localizedCaseInsensitiveContains(query)
        }
    }

    private var activeMarqueeRect: CGRect? {
        guard let marqueeStartPoint, let marqueeCurrentPoint, isDragSelecting else {
            return nil
        }
        return marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
    }

    var body: some View {
        if appState.lookupHistory.isEmpty {
            EmptyStateView(
                title: "还没有查词历史",
                subtitle: "先去上面的“查词”页查几个词，这里会按时间记录下来。"
            )
        } else {
            GeometryReader { proxy in
                let arrangement = resolvedPaneArrangement(
                    width: proxy.size.width,
                    preference: appState.settings.workspacePaneLayoutPreference,
                    automaticThreshold: 900
                )

                AdaptiveWorkspaceSplit(arrangement: arrangement) {
                    VStack(alignment: .leading, spacing: 12) {
                    if !appState.savedCaptureDrafts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Quick Capture 草稿".localized(in: appState.displayLanguage))
                                    .font(.headline)
                                Spacer()
                                Text("\(appState.savedCaptureDrafts.count)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(appState.savedCaptureDrafts.prefix(4)) { draft in
                                SavedCaptureDraftRow(draft: draft, language: appState.displayLanguage) {
                                    appState.restoreCaptureDraft(draft.id)
                                    openWindow(id: "capture")
                                }
                            }
                        }
                    }

                    TextField("按英文或中文过滤历史", text: $historySearch)

                    MultiSelectActionBar(
                        isSelecting: isSelecting,
                        selectedCount: selectedHistoryIDs.count,
                        totalCount: filteredHistory.count,
                        onToggleSelecting: toggleSelectionMode,
                        onToggleSelectAll: toggleSelectAllHistory,
                        onDelete: deleteSelectedHistory,
                        language: appState.displayLanguage
                    )

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredHistory) { record in
                                HistoryRow(
                                    record: record,
                                    isSelected: isSelecting ? selectedHistoryIDs.contains(record.id) : appState.selectedLookupHistoryID == record.id,
                                    showsSelectionControl: isSelecting,
                                    isChecked: selectedHistoryIDs.contains(record.id),
                                    language: appState.displayLanguage
                                ) {
                                    if ignoreNextTapAfterDrag {
                                        return
                                    }

                                    if isSelecting {
                                        appState.selectedLookupHistoryID = record.id
                                        toggleSelection(for: record.id)
                                    } else {
                                        appState.selectedLookupHistoryID = record.id
                                    }
                                }
                                .marqueeSelectableFrame(id: record.id, coordinateSpaceName: selectionSpaceName)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.35)
                                        .onEnded { _ in
                                            activateDirectSelection(for: record.id)
                                        }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .background(
                        ScrollViewResolver { scrollView in
                            if resolvedScrollView !== scrollView {
                                resolvedScrollView = scrollView
                            }
                        }
                    )
                    .marqueeViewportFrame(coordinateSpaceName: selectionSpaceName)
                }
                .padding(16)
                .frame(
                    minWidth: arrangement == .horizontal ? 240 : nil,
                    idealWidth: arrangement == .horizontal ? 300 : nil,
                    maxWidth: arrangement == .horizontal ? 360 : .infinity,
                    minHeight: arrangement == .vertical ? 220 : nil,
                    idealHeight: arrangement == .vertical ? 300 : nil,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .coordinateSpace(name: selectionSpaceName)
                .contentShape(Rectangle())
                .onPreferenceChange(MarqueeSelectionBoundsPreferenceKey.self) { frames in
                    rowFrames = frames
                    refreshMarqueeSelection()
                }
                .onPreferenceChange(MarqueeViewportFramePreferenceKey.self) { viewportFrame in
                    scrollViewportFrame = viewportFrame
                }
                .overlay(alignment: .topLeading) {
                    if let activeMarqueeRect {
                        MarqueeSelectionOverlay(rect: activeMarqueeRect)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(selectionSpaceName))
                        .onChanged { value in
                            updateMarqueeSelection(start: value.startLocation, current: value.location)
                        }
                        .onEnded { _ in
                            endMarqueeSelection()
                        }
                )
                .onChange(of: filteredHistory.map(\.id)) { _, historyIDs in
                    let visibleIDs = Set(historyIDs)
                    selectedHistoryIDs.formIntersection(visibleIDs)
                    if isSelecting, visibleIDs.isEmpty {
                        isSelecting = false
                    }
                    if !isSelecting {
                        isDragSelecting = false
                    }
                }
                .onDisappear {
                    stopAutoScroll()
                }

                } secondary: {
                    if let record = appState.selectedLookupHistoryRecord {
                        LookupDetailView(
                            record: record,
                            showsHistoryMeta: true,
                            onSelectReverseCandidate: nil,
                            prefersCompactChrome: arrangement == .vertical,
                            language: appState.displayLanguage,
                            voicePreference: appState.settings.pronunciationVoicePreference
                        )
                        .frame(
                            minWidth: arrangement == .horizontal ? 360 : nil,
                            idealWidth: arrangement == .horizontal ? 480 : nil,
                            maxWidth: .infinity,
                            minHeight: arrangement == .vertical ? 280 : nil,
                            maxHeight: .infinity,
                            alignment: .leading
                        )
                    } else {
                        EmptyStateView(
                            title: "选择一条历史",
                            subtitle: "这里会显示当时查到的释义、例句、翻译、搭配和发音。",
                            language: appState.displayLanguage
                        )
                        .frame(
                            minWidth: arrangement == .horizontal ? 360 : nil,
                            idealWidth: arrangement == .horizontal ? 480 : nil,
                            maxWidth: .infinity,
                            minHeight: arrangement == .vertical ? 280 : nil,
                            maxHeight: .infinity,
                            alignment: .center
                        )
                    }
                }
            }
        }
    }

    private func toggleSelectionMode() {
        isSelecting.toggle()
        resetMarqueeSelection()
        if !isSelecting {
            selectedHistoryIDs.removeAll()
        }
    }

    private func activateDirectSelection(for recordID: UUID) {
        ignoreNextTapAfterDrag = true
        appState.selectedLookupHistoryID = recordID
        isSelecting = true
        selectedHistoryIDs.insert(recordID)
        resetMarqueeSelection()
    }

    private func toggleSelection(for recordID: UUID) {
        if selectedHistoryIDs.contains(recordID) {
            selectedHistoryIDs.remove(recordID)
        } else {
            selectedHistoryIDs.insert(recordID)
        }
    }

    private func toggleSelectAllHistory() {
        let visibleIDs = Set(filteredHistory.map(\.id))
        if !visibleIDs.isEmpty, selectedHistoryIDs == visibleIDs {
            selectedHistoryIDs.removeAll()
        } else {
            selectedHistoryIDs = visibleIDs
        }
    }

    private func deleteSelectedHistory() {
        let recordIDs = selectedHistoryIDs
        guard !recordIDs.isEmpty else {
            return
        }

        appState.deleteLookupHistoryRecords(recordIDs)
        selectedHistoryIDs.removeAll()
        isSelecting = false
        resetMarqueeSelection()
    }

    private func updateMarqueeSelection(start: CGPoint, current: CGPoint) {
        if !isDragSelecting {
            marqueeBaseSelection = isSelecting ? selectedHistoryIDs : []
            if !isSelecting {
                isSelecting = true
                selectedHistoryIDs.removeAll()
                marqueeBaseSelection.removeAll()
            }
        }

        isDragSelecting = true
        ignoreNextTapAfterDrag = true
        marqueeStartPoint = start
        marqueeCurrentPoint = current
        refreshMarqueeSelection()
        updateAutoScroll(for: current)
    }

    private func endMarqueeSelection() {
        resetMarqueeSelection()
    }

    private func refreshMarqueeSelection() {
        guard isDragSelecting,
              let marqueeStartPoint,
              let marqueeCurrentPoint else {
            return
        }

        let rect = marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
        let intersectedIDs = Set<UUID>(filteredHistory.compactMap { record in
            guard let frame = rowFrames[record.id], frame.intersects(rect) else {
                return nil
            }
            return record.id
        })

        selectedHistoryIDs = marqueeBaseSelection.union(intersectedIDs)

        if let firstSelectedID = filteredHistory.first(where: { selectedHistoryIDs.contains($0.id) })?.id {
            appState.selectedLookupHistoryID = firstSelectedID
        }
    }

    private func updateAutoScroll(for point: CGPoint) {
        let velocity = marqueeAutoScrollVelocity(for: point, within: scrollViewportFrame)
        guard abs(velocity) > 0.1 else {
            stopAutoScroll()
            return
        }

        autoScrollVelocity = velocity
        guard autoScrollTask == nil else {
            return
        }

        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard isDragSelecting, let resolvedScrollView else {
                    break
                }

                _ = marqueeScroll(resolvedScrollView, verticalDelta: autoScrollVelocity)
                refreshMarqueeSelection()

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            autoScrollTask = nil
        }
    }

    private func stopAutoScroll() {
        autoScrollVelocity = 0
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func resetMarqueeSelection() {
        stopAutoScroll()
        isDragSelecting = false
        marqueeStartPoint = nil
        marqueeCurrentPoint = nil
        marqueeBaseSelection.removeAll()
        DispatchQueue.main.async {
            ignoreNextTapAfterDrag = false
        }
    }
}

private struct LookupStatusView: View {
    let title: String
    let subtitle: String
    let showsProgress: Bool
    var language: AppDisplayLanguage = .chinese

    var body: some View {
        VStack(spacing: 16) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
            }

            Text(title.localized(in: language))
                .font(.title2.weight(.semibold))

            Text(subtitle.localized(in: language))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

private struct SentenceEngineStatusCard: View {
    @ObservedObject var appState: AppState
    var language: AppDisplayLanguage = .chinese

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("句子引擎".localized(in: language))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(appState.sentenceEngineLookupStatusText.localized(in: language))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appState.sentenceEngineLookupStatusColor)
            }

            Text(appState.sentenceEngineLookupMessage.localized(in: language))
                .font(.footnote)
                .foregroundStyle(appState.sentenceEngineLookupMessageColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct ReviewWorkspace: View {
    @ObservedObject var appState: AppState
    private let reviewEngine = ReviewEngine()

    @State private var feedback: ReviewSessionFeedback?
    @State private var presentedCard: ReviewCard?
    @State private var pendingSessionItemIDs: [UUID] = []
    @State private var pendingSessionQuestionTypes = Set(ReviewQuestionType.allCases)
    @State private var showingReviewSessionConfigurator = false
    @State private var isDragSelecting = false
    @State private var ignoreNextTapAfterDrag = false
    @State private var marqueeStartPoint: CGPoint?
    @State private var marqueeCurrentPoint: CGPoint?
    @State private var marqueeBaseSelection: Set<UUID> = []
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var scrollViewportFrame: CGRect = .zero
    @State private var resolvedScrollView: NSScrollView?
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?

    private let selectionSpaceName = "ReviewMarqueeSelectionSpace"

    private var sourceCounts: [ReviewSourceKind: Int] {
        [
            .library: appState.libraryEntries.filter { $0.kind != .sentence }.count,
            .favorites: appState.libraryEntries.filter { $0.kind != .sentence && $0.isFavorite }.count,
            .history: uniqueHistoryRecordCount
        ]
    }

    private var displayedItems: [ReviewPickerItem] {
        var itemsByKey: [String: ReviewPickerItem] = [:]
        let libraryEntries = appState.libraryEntries.filter { $0.kind != .sentence }

        func preferredHistoryMatch(_ lhs: VocabEntry, _ rhs: VocabEntry) -> VocabEntry {
            if lhs.status != rhs.status {
                return lhs.status == .library ? lhs : rhs
            }

            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite ? lhs : rhs
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt ? lhs : rhs
            }

            return lhs.id.uuidString >= rhs.id.uuidString ? lhs : rhs
        }

        let entryLookupByKey = Dictionary(
            appState.entries
                .filter { $0.kind != .sentence }
                .map { (normalizedReviewKey($0.term), $0) }
                .filter { !$0.0.isEmpty },
            uniquingKeysWith: preferredHistoryMatch
        )

        func merge(
            entry: VocabEntry,
            backingEntryID: UUID?,
            source: ReviewSourceKind,
            key: String
        ) {
            if var existing = itemsByKey[key] {
                if existing.sourceKinds.contains(source) == false {
                    existing.sourceKinds.append(source)
                }
                itemsByKey[key] = existing
                return
            }

            itemsByKey[key] = ReviewPickerItem(
                id: entry.id,
                dedupeKey: key,
                entry: entry,
                backingEntryID: backingEntryID,
                sourceKinds: [source]
            )
        }

        if appState.selectedReviewSources.contains(.library) {
            for entry in libraryEntries {
                merge(
                    entry: entry,
                    backingEntryID: entry.id,
                    source: .library,
                    key: "entry:\(entry.id.uuidString)"
                )
            }
        }

        if appState.selectedReviewSources.contains(.favorites) {
            for entry in libraryEntries where entry.isFavorite {
                merge(
                    entry: entry,
                    backingEntryID: entry.id,
                    source: .favorites,
                    key: "entry:\(entry.id.uuidString)"
                )
            }
        }

        if appState.selectedReviewSources.contains(.history) {
            var seenHistoryKeys: Set<String> = []

            for record in appState.lookupHistory where record.content.kind != .sentence && record.status == .completed {
                let historyKey = normalizedReviewKey(record.content.term)
                guard !historyKey.isEmpty, seenHistoryKeys.insert(historyKey).inserted else {
                    continue
                }

                if let matchingEntry = entryLookupByKey[historyKey] {
                    merge(
                        entry: matchingEntry,
                        backingEntryID: matchingEntry.id,
                        source: .history,
                        key: "entry:\(matchingEntry.id.uuidString)"
                    )
                } else {
                    let historyEntry = historyProxyEntry(from: record)
                    merge(
                        entry: historyEntry,
                        backingEntryID: nil,
                        source: .history,
                        key: "history:\(historyKey)"
                    )
                }
            }
        }

        let rawItems = Array(itemsByKey.values)
        let orderedEntries = reviewEngine.orderedEntries(
            from: rawItems.map(\.entry),
            sort: appState.reviewSortOption,
            excludeMastered: appState.settings.excludeMasteredFromReview
        )
        let itemLookup = Dictionary(uniqueKeysWithValues: rawItems.map { ($0.entry.id, $0) })

        return orderedEntries.compactMap { itemLookup[$0.id] }
    }

    private var displayedItemsByID: [UUID: ReviewPickerItem] {
        Dictionary(uniqueKeysWithValues: displayedItems.map { ($0.id, $0) })
    }

    private var selectedItemsForSession: [ReviewPickerItem] {
        if appState.selectedReviewItemIDs.isEmpty {
            return displayedItems
        }

        let selectedIDs = appState.selectedReviewItemIDs
        return displayedItems.filter { selectedIDs.contains($0.id) }
    }

    private var currentSessionItems: [ReviewPickerItem] {
        appState.reviewSessionQueueIDs.compactMap { displayedItemsByID[$0] }
    }

    private var currentSessionItem: ReviewPickerItem? {
        currentSessionItems.first
    }

    private var activeMarqueeRect: CGRect? {
        guard let marqueeStartPoint, let marqueeCurrentPoint, isDragSelecting else {
            return nil
        }

        return marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
    }

    var body: some View {
        Group {
            if appState.isReviewSessionActive {
                sessionStage
            } else {
                setupStage
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.reviewSessionTotalCount)
        .onChange(of: displayedItems.map(\.id)) { _, itemIDs in
            appState.reconcileReviewState(with: Set(itemIDs))
        }
        .onChange(of: currentSessionItem?.id) { _, _ in
            refreshPresentedCard()
        }
        .task(id: displayedItems.map(\.id)) {
            appState.reconcileReviewState(with: Set(displayedItems.map(\.id)))
        }
        .task(id: currentSessionItem?.id) {
            refreshPresentedCard()
        }
        .sheet(isPresented: $showingReviewSessionConfigurator, onDismiss: clearPendingSessionIfNeeded) {
            ReviewSessionConfiguratorSheet(
                itemCount: pendingSessionItemIDs.count,
                selectedQuestionTypes: $pendingSessionQuestionTypes,
                onStart: startSession,
                onCancel: {
                    pendingSessionItemIDs = []
                    showingReviewSessionConfigurator = false
                }
            )
            .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 460)
        }
        .onDisappear {
            stopAutoScroll()
        }
    }

    private var setupStage: some View {
        GeometryReader { proxy in
                let arrangement = resolvedPaneArrangement(
                    width: proxy.size.width,
                    preference: appState.settings.workspacePaneLayoutPreference,
                    automaticThreshold: 900
                )

            AdaptiveWorkspaceSplit(arrangement: arrangement) {
                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("先选这一轮要复习的词")
                        .font(.largeTitle.weight(.semibold))

                    Text("来源、排序、多选和滑动框选都在这里。没手动勾选时，会默认复习当前筛选下的全部词。")
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ReviewSourceKind.allCases) { source in
                            ReviewSourceChip(
                                source: source,
                                count: sourceCounts[source, default: 0],
                                isSelected: appState.selectedReviewSources.contains(source)
                            ) {
                                toggleSource(source)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack(spacing: 12) {
                    Picker("排序", selection: $appState.reviewSortOption) {
                        ForEach(ReviewSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    ReviewSelectionActionBar(
                        isSelecting: appState.isSelectingReviewItems,
                        selectedCount: appState.selectedReviewItemIDs.count,
                        totalCount: displayedItems.count,
                        onToggleSelecting: toggleSelectionMode,
                        onToggleSelectAll: toggleSelectAll,
                        onClearSelection: { appState.selectedReviewItemIDs.removeAll() }
                    )

                    Spacer()

                    Text(appState.selectedReviewItemIDs.isEmpty ? "将复习 \(displayedItems.count) 个词" : "已选 \(appState.selectedReviewItemIDs.count) 个词")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Button(appState.selectedReviewItemIDs.isEmpty ? "开始复习全部" : "开始复习已选") {
                        presentSessionModePicker()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedItemsForSession.isEmpty)
                }

                VStack(spacing: 0) {
                    if displayedItems.isEmpty {
                        ReviewEmptySelectionState(
                            hasSelectedSources: appState.selectedReviewSources.isEmpty == false
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(displayedItems) { item in
                                    ReviewPickerRow(
                                        item: item,
                                        isSelected: appState.selectedReviewItemIDs.contains(item.id),
                                        showsSelectionControl: appState.isSelectingReviewItems
                                    ) {
                                        if ignoreNextTapAfterDrag {
                                            return
                                        }

                                        if appState.isSelectingReviewItems {
                                            toggleSelection(for: item.id)
                                        } else {
                                            appState.isSelectingReviewItems = true
                                            appState.selectedReviewItemIDs = [item.id]
                                        }
                                    }
                                    .marqueeSelectableFrame(id: item.id, coordinateSpaceName: selectionSpaceName)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .background(
                            ScrollViewResolver { scrollView in
                                if resolvedScrollView !== scrollView {
                                    resolvedScrollView = scrollView
                                }
                            }
                        )
                        .marqueeViewportFrame(coordinateSpaceName: selectionSpaceName)
                    }
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .coordinateSpace(name: selectionSpaceName)
                .contentShape(Rectangle())
                .onPreferenceChange(MarqueeSelectionBoundsPreferenceKey.self) { frames in
                    rowFrames = frames
                    refreshMarqueeSelection()
                }
                .onPreferenceChange(MarqueeViewportFramePreferenceKey.self) { viewportFrame in
                    scrollViewportFrame = viewportFrame
                }
                .overlay(alignment: .topLeading) {
                    if let activeMarqueeRect {
                        MarqueeSelectionOverlay(rect: activeMarqueeRect)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(selectionSpaceName))
                        .onChanged { value in
                            updateMarqueeSelection(start: value.startLocation, current: value.location)
                        }
                        .onEnded { _ in
                            endMarqueeSelection()
                        }
                )
                }
                .padding(28)
                .frame(
                    minWidth: arrangement == .horizontal ? 360 : nil,
                    idealWidth: arrangement == .horizontal ? 620 : nil,
                    maxWidth: arrangement == .horizontal ? .infinity : .infinity,
                    minHeight: arrangement == .vertical ? 320 : nil,
                    idealHeight: arrangement == .vertical ? 420 : nil,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            } secondary: {
                ReviewHistoryPanel(history: appState.reviewHistory)
                    .frame(
                        minWidth: arrangement == .horizontal ? 240 : nil,
                        idealWidth: arrangement == .horizontal ? 300 : nil,
                        maxWidth: arrangement == .horizontal ? 360 : .infinity,
                        minHeight: arrangement == .vertical ? 220 : nil,
                        idealHeight: arrangement == .vertical ? 260 : nil,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
        }
    }

    @ViewBuilder
    private var sessionStage: some View {
        if let currentItem = currentSessionItem,
           let presentedCard,
           presentedCard.entryID == currentItem.id {
            ReviewCardView(
                card: presentedCard,
                entry: currentItem.entry,
                progressText: "\(appState.reviewCompletedCount + 1) / \(max(appState.reviewSessionTotalCount, 1))",
                sessionStyleTitle: appState.reviewSessionConfiguration.title,
                sessionStyleDetail: appState.reviewSessionConfiguration.detail,
                sourceSummary: currentItem.sourceSummary,
                showsHistoryOnlyHint: currentItem.isHistoryOnly,
                draft: $appState.reviewAnswerDraft,
                onPreviousCard: navigateToPreviousCard,
                onNextCard: navigateToNextCard,
                onAdvanceWithDefaultDecision: {
                    handleDecisionForCurrentItem(currentItem, decision: presentedCardAutoDecision(for: presentedCard))
                },
                onDecision: { decision in
                    handleDecision(decision, for: currentItem)
                },
                onEndSession: { appState.resetReviewSession() }
            )
            .overlay(alignment: .top) {
                if let feedback {
                    ReviewFeedbackBanner(feedback: feedback)
                        .padding(.top, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        } else if currentSessionItem != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(spacing: 18) {
                Text("这一轮复习完成")
                    .font(.largeTitle.weight(.semibold))

                Text("一共过了 \(appState.reviewCompletedCount) 个词。你可以回到选词界面继续挑，也可以马上再来一轮。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("重新选词") {
                        appState.resetReviewSession()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("再来一轮相同筛选") {
                        let itemIDs = selectedItemsForSession.map(\.id)
                        appState.startReviewSession(with: itemIDs, configuration: appState.reviewSessionConfiguration)
                        feedback = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(28)
        }
    }

    private var uniqueHistoryRecordCount: Int {
        var seen: Set<String> = []
        var count = 0

        for record in appState.lookupHistory where record.content.kind != .sentence && record.status == .completed {
            let key = normalizedReviewKey(record.content.term)
            guard !key.isEmpty, seen.insert(key).inserted else {
                continue
            }
            count += 1
        }

        return count
    }

    private func normalizedReviewKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func historyProxyEntry(from record: LookupHistoryRecord) -> VocabEntry {
        let meanings = Array(
            record.content.meanings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniqued()
                .prefix(EntryCandidateDefaults.meaningChoiceCount)
        )
        let exampleChoices = record.content.examples.prefix(1).compactMap { example in
            let english = example.english.trimmingCharacters(in: .whitespacesAndNewlines)
            let chinese = example.chinese.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = [english, chinese].filter { !$0.isEmpty }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }

        return VocabEntry(
            id: record.id,
            createdAt: record.queriedAt,
            updatedAt: record.queriedAt,
            kind: record.content.kind,
            term: record.content.term,
            sourceContext: record.originalQuery == record.content.term ? "" : record.originalQuery,
            proficiency: .unknown,
            status: .library,
            partOfSpeech: record.content.partOfSpeech,
            meaningChoices: meanings,
            meaningGroups: record.content.meaningGroups,
            selectedMeaningIndexes: meanings.isEmpty ? [] : [0],
            generatedExamples: exampleChoices,
            selectedExampleIndexes: exampleChoices.isEmpty ? [] : [0],
            englishDefinitions: record.content.englishDefinitions,
            englishSynonyms: record.content.englishSynonyms,
            inflectionLines: record.content.inflectionLines,
            referenceTags: record.content.referenceTags,
            notes: "",
            isFavorite: false,
            reviewCount: 0,
            lastReviewedAt: nil
        )
    }

    private func toggleSource(_ source: ReviewSourceKind) {
        if appState.selectedReviewSources.contains(source) {
            appState.selectedReviewSources.remove(source)
        } else {
            appState.selectedReviewSources.insert(source)
        }
    }

    private func toggleSelectionMode() {
        appState.isSelectingReviewItems.toggle()
        resetMarqueeSelection()

        if !appState.isSelectingReviewItems {
            appState.selectedReviewItemIDs.removeAll()
        }
    }

    private func toggleSelection(for itemID: UUID) {
        if appState.selectedReviewItemIDs.contains(itemID) {
            appState.selectedReviewItemIDs.remove(itemID)
        } else {
            appState.selectedReviewItemIDs.insert(itemID)
        }
    }

    private func toggleSelectAll() {
        let visibleIDs = Set(displayedItems.map(\.id))
        if !visibleIDs.isEmpty, appState.selectedReviewItemIDs == visibleIDs {
            appState.selectedReviewItemIDs.removeAll()
        } else {
            appState.selectedReviewItemIDs = visibleIDs
        }
    }

    private func presentSessionModePicker() {
        let items = selectedItemsForSession
        guard !items.isEmpty else {
            return
        }

        pendingSessionItemIDs = items.map(\.id)
        let existingSelection = Set(appState.reviewSessionConfiguration.orderedQuestionTypes)
        pendingSessionQuestionTypes = existingSelection.isEmpty ? Set(ReviewQuestionType.allCases) : existingSelection
        showingReviewSessionConfigurator = true
    }

    private func startSession() {
        guard !pendingSessionItemIDs.isEmpty else {
            return
        }

        let configuration = ReviewSessionConfiguration(questionTypes: Array(pendingSessionQuestionTypes))
        guard configuration.orderedQuestionTypes.isEmpty == false else {
            return
        }

        appState.startReviewSession(with: pendingSessionItemIDs, configuration: configuration)
        feedback = nil
        pendingSessionItemIDs = []
        showingReviewSessionConfigurator = false
    }

    private func navigateToPreviousCard() {
        feedback = nil
        appState.moveToPreviousReviewItem()
    }

    private func navigateToNextCard() {
        feedback = nil
        appState.moveToNextReviewItem()
    }

    private func handleDecision(_ decision: ReviewDecision, for item: ReviewPickerItem) {
        let card = presentedCard ?? reviewEngine.card(
            for: item.entry,
            within: currentSessionItems.map(\.entry),
            sessionConfiguration: appState.reviewSessionConfiguration
        )
        appState.completeReviewDecision(
            decision,
            backingEntryID: item.backingEntryID,
            itemID: item.id,
            term: item.entry.term,
            meaning: item.entry.preferredMeaning,
            mode: card.mode,
            sourceKinds: item.orderedSourceKinds,
            isHistoryOnly: item.isHistoryOnly
        )
        showFeedback(for: decision)
    }

    private func handleDecisionForCurrentItem(_ item: ReviewPickerItem, decision: ReviewDecision) {
        guard currentSessionItem?.id == item.id else {
            return
        }

        handleDecision(decision, for: item)
    }

    private func presentedCardAutoDecision(for card: ReviewCard?) -> ReviewDecision {
        guard let card else {
            return .keep
        }

        switch card.questionType {
        case .flashcards:
            return .upgrade
        case .multipleChoice:
            return appState.reviewAnswerDraft.selectedChoice == card.answer ? .upgrade : .downgrade
        case .fillIn:
            return card.matchesSubmittedAnswer(appState.reviewAnswerDraft.typedAnswer) ? .upgrade : .downgrade
        }
    }

    private func refreshPresentedCard() {
        guard let currentItem = currentSessionItem else {
            presentedCard = nil
            return
        }

        presentedCard = reviewEngine.card(
            for: currentItem.entry,
            within: currentSessionItems.map(\.entry),
            sessionConfiguration: appState.reviewSessionConfiguration
        )
    }

    private func clearPendingSessionIfNeeded() {
        if showingReviewSessionConfigurator == false, pendingSessionItemIDs.isEmpty == false {
            pendingSessionItemIDs = []
        }
    }

    private func updateMarqueeSelection(start: CGPoint, current: CGPoint) {
        if !isDragSelecting {
            marqueeBaseSelection = appState.isSelectingReviewItems ? appState.selectedReviewItemIDs : []
            if !appState.isSelectingReviewItems {
                appState.isSelectingReviewItems = true
                appState.selectedReviewItemIDs.removeAll()
                marqueeBaseSelection.removeAll()
            }
        }

        isDragSelecting = true
        ignoreNextTapAfterDrag = true
        marqueeStartPoint = start
        marqueeCurrentPoint = current
        refreshMarqueeSelection()
        updateAutoScroll(for: current)
    }

    private func endMarqueeSelection() {
        resetMarqueeSelection()
    }

    private func refreshMarqueeSelection() {
        guard isDragSelecting,
              let marqueeStartPoint,
              let marqueeCurrentPoint else {
            return
        }

        let rect = marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
        let intersectedIDs = Set<UUID>(displayedItems.compactMap { item in
            guard let frame = rowFrames[item.id], frame.intersects(rect) else {
                return nil
            }
            return item.id
        })

        appState.selectedReviewItemIDs = marqueeBaseSelection.union(intersectedIDs)

        if !appState.selectedReviewItemIDs.isEmpty {
            appState.isSelectingReviewItems = true
        }
    }

    private func updateAutoScroll(for point: CGPoint) {
        let velocity = marqueeAutoScrollVelocity(for: point, within: scrollViewportFrame)
        guard abs(velocity) > 0.1 else {
            stopAutoScroll()
            return
        }

        autoScrollVelocity = velocity
        guard autoScrollTask == nil else {
            return
        }

        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard isDragSelecting, let resolvedScrollView else {
                    break
                }

                _ = marqueeScroll(resolvedScrollView, verticalDelta: autoScrollVelocity)
                refreshMarqueeSelection()
                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            autoScrollTask = nil
        }
    }

    private func stopAutoScroll() {
        autoScrollVelocity = 0
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func resetMarqueeSelection() {
        stopAutoScroll()
        isDragSelecting = false
        marqueeStartPoint = nil
        marqueeCurrentPoint = nil
        marqueeBaseSelection.removeAll()

        DispatchQueue.main.async {
            ignoreNextTapAfterDrag = false
        }
    }

    private func showFeedback(for decision: ReviewDecision) {
        let newFeedback = ReviewSessionFeedback.make(for: decision)

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            feedback = newFeedback
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)

            guard feedback?.id == newFeedback.id else {
                return
            }

            withAnimation(.easeOut(duration: 0.2)) {
                feedback = nil
            }
        }
    }
}

private struct EntryEditorView: View {
    @Binding var entry: VocabEntry
    let isGenerating: Bool
    let duplicateCount: Int
    let showsReferenceTags: Bool
    let onToggleFavorite: (() -> Void)?
    let onRegenerate: () -> Void
    let onPrimaryAction: (() -> Bool)?
    let primaryActionTitle: String?
    let onSecondaryAction: () -> Void
    let onMerge: (() -> Void)?
    var language: AppDisplayLanguage = .chinese

    @State private var showSelectionErrors = false
    @State private var editableMeaningCandidates: [CaptureMeaningCandidate] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("类型".localized(in: language), selection: $entry.kind) {
                                ForEach(EntryKind.allCases) { kind in
                                    Text(kind.title.localized(in: language)).tag(kind)
                                }
                            }
                            .pickerStyle(.segmented)

                            TextField(entry.kind.fieldPlaceholder.localized(in: language), text: $entry.term)
                                .font(.title2.weight(.semibold))
                            Text("\("录入于 ".localized(in: language))\(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            if let onToggleFavorite {
                                Button {
                                    onToggleFavorite()
                                } label: {
                                    Label((entry.isFavorite ? "已收藏" : "收藏").localized(in: language), systemImage: entry.isFavorite ? "heart.fill" : "heart")
                                }
                                .buttonStyle(.bordered)
                            }

                            Picker("熟练度".localized(in: language), selection: $entry.proficiency) {
                                ForEach(ProficiencyLevel.allCases) { level in
                                    Text(level.title.localized(in: language)).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    CaptureMeaningCandidatesSection(
                        title: "中文释义候选".localized(in: language),
                        candidates: $editableMeaningCandidates,
                        entryKind: entry.kind,
                        language: language
                    )

                    EditableChoicesSection(
                        title: "系统例句候选".localized(in: language),
                        entries: $entry.generatedExamples,
                        selectedIndexes: $entry.selectedExampleIndexes,
                        showsValidationError: showSelectionErrors && entry.hasAvailableExamples && !entry.hasSelectedExample,
                        maxEntryCount: EntryCandidateDefaults.exampleChoiceCount,
                        language: language
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("你遇到它时的原句".localized(in: language))
                            .font(.headline)
                        TextField(
                            "原句".localized(in: language),
                            text: $entry.sourceContext,
                            axis: .vertical
                        )
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

                    EnglishDefinitionSection(
                        title: "英文释义".localized(in: language),
                        definitions: entry.englishDefinitions,
                        synonyms: entry.englishSynonyms,
                        language: language
                    )

                    SimpleTextCardsSection(
                        title: "词形变化 / 词形关系".localized(in: language),
                        lines: localizedInflectionLines
                    )

                    HStack(alignment: .center, spacing: 12) {
                        Text("备注".localized(in: language))
                            .font(.headline)
                            .frame(width: 56, alignment: .leading)

                        TextField(
                            "备注".localized(in: language),
                            text: $entry.notes,
                            axis: .vertical
                        )
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

                    GenerationStatusSection(entry: entry, isGenerating: isGenerating, language: language)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .padding(.bottom, 8)
            }
            .textSelection(.enabled)

            Divider()

            HStack(spacing: 12) {
                Button("刷新候选".localized(in: language)) {
                    onRegenerate()
                }
                .disabled(isGenerating)
                .buttonStyle(.bordered)

                Button("删除词条".localized(in: language), role: .destructive) {
                    onSecondaryAction()
                }
                .buttonStyle(.bordered)

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }

                if let onMerge, duplicateCount > 0 {
                    Button("\("合并 ".localized(in: language))\(duplicateCount)\(" 个重复词条".localized(in: language))") {
                        onMerge()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let onPrimaryAction, let primaryActionTitle {
                    Button(primaryActionTitle.localized(in: language)) {
                        showSelectionErrors = !onPrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            syncEditableMeaningCandidates()
        }
        .onChange(of: entry.id) { _, _ in
            syncEditableMeaningCandidates()
        }
        .onChange(of: entry.meaningCandidates) { _, _ in
            syncEditableMeaningCandidatesIfNeeded()
        }
        .onChange(of: editableMeaningCandidates) { _, newValue in
            if entry.meaningCandidates != newValue {
                entry.applyMeaningCandidates(newValue)
            }
        }
    }

    private var localizedInflectionLines: [String] {
        entry.inflectionLines.map { language.localizedInflectionLine($0) }
    }

    private var localizedReferenceTags: [String] {
        entry.referenceTags.map { language.localizedReferenceTag($0) }
    }

    private func syncEditableMeaningCandidates() {
        editableMeaningCandidates = entry.meaningCandidates
    }

    private func syncEditableMeaningCandidatesIfNeeded() {
        let nextCandidates = entry.meaningCandidates
        if nextCandidates != editableMeaningCandidates {
            editableMeaningCandidates = nextCandidates
        }
    }
}

private struct LibraryStudyView: View {
    let entry: VocabEntry
    let showsReferenceTags: Bool
    var language: AppDisplayLanguage = .chinese

    private var selectedMeaningLines: [String] {
        let selectedCandidates = entry.meaningCandidates.filter(\.isSelected)
        let lines = selectedCandidates.compactMap { candidate -> String? in
            let line = DisplayFormatting.prefixedMeaning(
                candidate.meaning,
                partOfSpeech: candidate.partOfSpeech,
                kind: entry.kind
            )
            return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : line
        }

        if !lines.isEmpty {
            return lines
        }

        return entry.selectedMeanings
    }

    private var selectedExampleLines: [String] {
        entry.selectedExampleIndexes.compactMap { index in
            guard entry.generatedExamples.indices.contains(index) else {
                return nil
            }
            let line = entry.generatedExamples[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
    }

    private var localizedInflectionLines: [String] {
        entry.inflectionLines.map { language.localizedInflectionLine($0) }
    }

    private var localizedReferenceTags: [String] {
        entry.referenceTags.map { language.localizedReferenceTag($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.term)
                            .font(.title.weight(.semibold))
                        Text("\(entry.kind.title.localized(in: language)) · \("熟练度".localized(in: language)) \(entry.proficiency.title.localized(in: language))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if entry.isFavorite {
                        Label("已收藏".localized(in: language), systemImage: "heart.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if !selectedMeaningLines.isEmpty {
                    SimpleTextCardsSection(
                        title: "当前学习释义".localized(in: language),
                        lines: selectedMeaningLines
                    )
                }

                if !selectedExampleLines.isEmpty {
                    SimpleTextCardsSection(
                        title: "当前学习例句".localized(in: language),
                        lines: selectedExampleLines
                    )
                }

                if !entry.sourceContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SimpleTextCardsSection(
                        title: "原句".localized(in: language),
                        lines: [entry.sourceContext]
                    )
                }

                EnglishDefinitionSection(
                    title: "英文释义".localized(in: language),
                    definitions: entry.englishDefinitions,
                    synonyms: entry.englishSynonyms,
                    language: language
                )

                if !localizedInflectionLines.isEmpty {
                    SimpleTextCardsSection(
                        title: "词形变化 / 词形关系".localized(in: language),
                        lines: localizedInflectionLines
                    )
                }

                if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SimpleTextCardsSection(
                        title: "备注".localized(in: language),
                        lines: [entry.notes]
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .textSelection(.enabled)
    }
}

private struct GenerationStatusSection: View {
    let entry: VocabEntry
    let isGenerating: Bool
    var language: AppDisplayLanguage = .chinese

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("生成状态".localized(in: language))
                        .font(.headline)

                    Spacer()

                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if let generatedAt = entry.lastGeneratedAt {
                Text("\("最近时间：".localized(in: language))\(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("最近时间：暂无".localized(in: language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\("当前：".localized(in: language))\((isGenerating ? "正在生成" : "空闲").localized(in: language))")

                    if let source = entry.lastGenerationSource {
                        Text("\("最近来源：".localized(in: language))\(source.title.localized(in: language))")
                    }

                    if let trigger = entry.lastGenerationTrigger {
                        Text("\("触发方式：".localized(in: language))\(trigger.title.localized(in: language))")
                    }

                    if let model = entry.lastGenerationModel, !model.isEmpty {
                        Text("\("模型：".localized(in: language))\(model)")
                    }

                    if let reason = entry.lastGenerationReasonDescription {
                        Text("\("原因：".localized(in: language))\(reason.localized(in: language))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct EditableChoicesSection: View {
    let title: String
    @Binding var entries: [String]
    @Binding var selectedIndexes: [Int]
    let showsValidationError: Bool
    let maxEntryCount: Int
    var entryPrefixes: [String] = []
    var headerAccessory: AnyView? = nil
    var language: AppDisplayLanguage = .chinese
    var alwaysShowsCustomDraftField = false
    var customDraftPlaceholder: String?

    @State private var editingIndex: Int?
    @State private var customDraftText = ""
    @State private var customDraftMessage: String?
    @FocusState private var focusedFieldIndex: Int?
    @FocusState private var focusedCustomDraftField: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)

                if let headerAccessory {
                    headerAccessory
                }

                Spacer()

                Button {
                    guard entries.count < maxEntryCount else {
                        return
                    }
                    entries.append("")
                } label: {
                    Label("添加候选".localized(in: language), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(entries.count >= maxEntryCount)
                .help("\("最多添加 ".localized(in: language))\(maxEntryCount)\(" 个候选".localized(in: language))")

                Button {
                    deleteSelectedRows()
                } label: {
                    Label("删除已选".localized(in: language), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndexes.isEmpty)
                .help("删除当前勾选的候选框".localized(in: language))
            }

            ForEach(entries.indices, id: \.self) { index in
                choiceRow(for: index)
            }

            if alwaysShowsCustomDraftField {
                customDraftRow
            }

            if showsValidationError {
                Text("至少选择一个候选。".localized(in: language))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: focusedFieldIndex) {
            if focusedFieldIndex == nil {
                editingIndex = nil
            }
        }
        .onChange(of: focusedCustomDraftField) {
            if !focusedCustomDraftField {
                commitCustomDraft()
            }
        }
        .onChange(of: entries) {
            if entries.count < maxEntryCount {
                customDraftMessage = nil
            }
        }
        .onChange(of: customDraftText) {
            if customDraftMessage != nil {
                customDraftMessage = nil
            }
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { entries.indices.contains(index) ? entries[index] : "" },
            set: { newValue in
                guard entries.indices.contains(index) else {
                    return
                }
                entries[index] = newValue
            }
        )
    }

    @ViewBuilder
    private func choiceRow(for index: Int) -> some View {
        let isSelected = selectedIndexes.contains(index)
        let entryPrefix = prefix(for: index)

        if editingIndex == index {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    toggleSelection(for: index)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(.top, 6)
                }
                .buttonStyle(.plain)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let entryPrefix {
                        prefixBadge(entryPrefix)
                    }

                    TextField(placeholder(for: index), text: binding(for: index))
                        .textFieldStyle(.plain)
                        .focused($focusedFieldIndex, equals: index)
                        .onSubmit {
                            editingIndex = nil
                            focusedFieldIndex = nil
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor(isSelected: isSelected), lineWidth: 1)
                )
            }
        } else {
            Button {
                toggleSelection(for: index)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(.top, 6)

                    HStack(alignment: .top, spacing: 10) {
                        if let entryPrefix {
                            prefixBadge(entryPrefix)
                                .padding(.top, 1)
                        }

                        Text(entries[index].isEmpty ? placeholder(for: index) : entries[index])
                            .foregroundStyle(entries[index].isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor(isSelected: isSelected), lineWidth: 1)
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        ensureSelected(index)
                        editingIndex = index
                        DispatchQueue.main.async {
                            focusedFieldIndex = index
                        }
                    }
            )
        }
    }

    private func placeholder(for index: Int) -> String {
        language.text("候选 \(index + 1)", "Candidate \(index + 1)")
    }

    private var resolvedCustomDraftPlaceholder: String {
        let cleanedPlaceholder = customDraftPlaceholder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanedPlaceholder.isEmpty
            ? language.text("（自定义内容）", "(Custom entry)")
            : cleanedPlaceholder
    }

    private var customDraftRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                TextField(resolvedCustomDraftPlaceholder, text: $customDraftText)
                    .textFieldStyle(.plain)
                    .focused($focusedCustomDraftField)
                    .onSubmit {
                        commitCustomDraft()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                focusedCustomDraftField
                                    ? Color.accentColor.opacity(0.7)
                                    : Color(nsColor: .separatorColor),
                                lineWidth: 1
                            )
                    )
            }

            if let customDraftMessage, !customDraftMessage.isEmpty {
                Text(customDraftMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.leading, 34)
            }
        }
    }

    private func prefix(for index: Int) -> String? {
        guard entryPrefixes.indices.contains(index) else {
            return nil
        }

        let prefix = entryPrefixes[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? nil : prefix
    }

    private func prefixBadge(_ prefix: String) -> some View {
        Text(prefix)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
    }

    private func toggleSelection(for index: Int) {
        if let existingIndex = selectedIndexes.firstIndex(of: index) {
            selectedIndexes.remove(at: existingIndex)
        } else {
            selectedIndexes.append(index)
            selectedIndexes.sort()
        }
    }

    private func ensureSelected(_ index: Int) {
        if !selectedIndexes.contains(index) {
            selectedIndexes.append(index)
            selectedIndexes.sort()
        }
    }

    private func borderColor(isSelected: Bool) -> Color {
        if showsValidationError {
            return .red
        }

        return isSelected ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor)
    }

    private func deleteSelectedRows() {
        let selectedSet = Set(selectedIndexes)
        entries = entries.enumerated()
            .filter { !selectedSet.contains($0.offset) }
            .map(\.element)
        selectedIndexes = selectedIndexes
            .filter { !selectedSet.contains($0) }
            .map { originalIndex in
                originalIndex - selectedSet.filter { $0 < originalIndex }.count
            }
        editingIndex = nil
        focusedFieldIndex = nil
    }

    private func commitCustomDraft() {
        let cleanedDraft = customDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDraft.isEmpty else {
            customDraftMessage = nil
            return
        }

        if let existingIndex = entries.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(cleanedDraft) == .orderedSame
        }) {
            ensureSelected(existingIndex)
            customDraftText = ""
            customDraftMessage = nil
            return
        }

        if let emptyIndex = entries.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            entries[emptyIndex] = cleanedDraft
            ensureSelected(emptyIndex)
            customDraftText = ""
            customDraftMessage = nil
            return
        }

        guard entries.count < maxEntryCount else {
            customDraftMessage = language.text(
                "最多保留 5 个意思，先删一个再加新的自定义意思。",
                "You can keep up to 5 meanings. Delete one before adding another custom meaning."
            )
            return
        }

        entries.append(cleanedDraft)
        ensureSelected(entries.count - 1)
        customDraftText = ""
        customDraftMessage = nil
    }
}

private struct LookupDetailView: View {
    @State private var detailScrollOffset: CGFloat = 0

    let record: LookupHistoryRecord
    let showsHistoryMeta: Bool
    let onSelectReverseCandidate: ((ReverseLookupCandidate) -> Void)?
    let onOpenInQuickCapture: (() -> Void)?
    let onQuickSaveToLibrary: (() -> Void)?
    let isInLibrary: Bool
    let onOpenReverseCandidateInQuickCapture: ((ReverseLookupCandidate) -> Void)?
    let loadingMessage: String?
    let isLoadingExamples: Bool
    let showsReferenceTags: Bool
    let prefersCompactChrome: Bool
    let showsStickyQuickCaptureAction: Bool
    let language: AppDisplayLanguage
    let voicePreference: PronunciationVoicePreference

    init(
        record: LookupHistoryRecord,
        showsHistoryMeta: Bool,
        onSelectReverseCandidate: ((ReverseLookupCandidate) -> Void)?,
        onOpenInQuickCapture: (() -> Void)? = nil,
        onQuickSaveToLibrary: (() -> Void)? = nil,
        isInLibrary: Bool = false,
        onOpenReverseCandidateInQuickCapture: ((ReverseLookupCandidate) -> Void)? = nil,
        loadingMessage: String? = nil,
        isLoadingExamples: Bool = false,
        showsReferenceTags: Bool = false,
        prefersCompactChrome: Bool = false,
        showsStickyQuickCaptureAction: Bool = false,
        language: AppDisplayLanguage = .chinese,
        voicePreference: PronunciationVoicePreference = .automatic
    ) {
        self.record = record
        self.showsHistoryMeta = showsHistoryMeta
        self.onSelectReverseCandidate = onSelectReverseCandidate
        self.onOpenInQuickCapture = onOpenInQuickCapture
        self.onQuickSaveToLibrary = onQuickSaveToLibrary
        self.isInLibrary = isInLibrary
        self.onOpenReverseCandidateInQuickCapture = onOpenReverseCandidateInQuickCapture
        self.loadingMessage = loadingMessage
        self.isLoadingExamples = isLoadingExamples
        self.showsReferenceTags = showsReferenceTags
        self.prefersCompactChrome = prefersCompactChrome
        self.showsStickyQuickCaptureAction = showsStickyQuickCaptureAction
        self.language = language
        self.voicePreference = voicePreference
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: prefersCompactChrome ? 14 : 18) {
                Group {
                    VStack(alignment: .leading, spacing: prefersCompactChrome ? 10 : 12) {
                        detailHeaderContent
                        pronunciationChrome
                    }
                }

                if record.reverseLookupCandidates.isEmpty,
                   let onOpenInQuickCapture {
                    Button(language.text("快速录入", "Quick Capture")) {
                        onOpenInQuickCapture()
                    }
                    .buttonStyle(.bordered)
                }

                if let loadingMessage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(loadingMessage.localized(in: language))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let historyStatusMessage {
                    infoBlock(title: "查询状态".localized(in: language)) {
                        Text(historyStatusMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(statusForegroundStyle)
                    }
                }

                infoBlock(title: meaningsTitle) {
                    if meaningSections.isEmpty, loadingMessage != nil {
                        Text("正在加载中文释义...".localized(in: language))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.secondary)
                    } else if meaningSections.isEmpty {
                        Text(meaningsFallbackMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(meaningSections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(section.lines, id: \.self) { line in
                                        meaningRow(line)
                                    }
                                }
                            }
                        }
                    }
                }

                if !record.reverseLookupCandidates.isEmpty {
                    infoBlock(title: "英文候选".localized(in: language)) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(record.reverseLookupCandidates) { candidate in
                                ReverseLookupCandidateRow(
                                    candidate: candidate,
                                    action: onSelectReverseCandidate,
                                    onOpenInQuickCapture: onOpenReverseCandidateInQuickCapture,
                                    prefersCompactActions: prefersCompactChrome,
                                    language: language
                                )
                            }
                        }
                    }
                }

                EnglishDefinitionSection(
                    title: "英文释义".localized(in: language),
                    definitions: record.content.englishDefinitions,
                    synonyms: record.content.englishSynonyms,
                    language: language,
                    prefersCompactChrome: prefersCompactChrome
                )

                if !record.content.inflectionLines.isEmpty, record.content.kind != .sentence {
                    supplementaryInfoSection(
                        title: "词形变化 / 词形关系".localized(in: language),
                        isInitiallyExpanded: !prefersCompactChrome
                    ) {
                        SimpleTextCards(lines: localizedInflectionLines, compact: prefersCompactChrome)
                    }
                }

                if showsReferenceTags, !record.content.referenceTags.isEmpty {
                    supplementaryInfoSection(
                        title: "词频 / 词典标签".localized(in: language),
                        isInitiallyExpanded: false
                    ) {
                        FlowTagsView(tags: localizedReferenceTags, compact: prefersCompactChrome)
                    }
                }

                if !record.content.examples.isEmpty || isLoadingExamples {
                    infoBlock(title: examplesTitle) {
                        if record.content.examples.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在补充例句...".localized(in: language))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(record.content.examples) { example in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(example.english)
                                        Text(example.chinese)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }

                if record.content.kind != .sentence {
                    supplementaryInfoSection(
                        title: "常见搭配 / 短语".localized(in: language),
                        isInitiallyExpanded: false
                    ) {
                        if record.content.collocations.isEmpty, loadingMessage != nil {
                            Text("正在补充常见搭配...".localized(in: language))
                                .foregroundStyle(.secondary)
                        } else if record.content.collocations.isEmpty {
                            Text("这次结果里没有给出实用搭配。".localized(in: language))
                                .foregroundStyle(.secondary)
                        } else {
                            FlowTagsView(tags: record.content.collocations, compact: prefersCompactChrome)
                        }
                    }
                }

                if showsHistoryMeta {
                    infoBlock(title: "这次查词记录".localized(in: language)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\("时间：".localized(in: language))\(record.queriedAt.formatted(date: .abbreviated, time: .shortened))")
                            if trimmedOriginalQuery != record.content.term {
                                Text("\("原始查询：".localized(in: language))\(trimmedOriginalQuery)")
                            }
                            Text("\("来源：".localized(in: language))\(record.source.title.localized(in: language))")
                            Text("\("学习动作：".localized(in: language))\(record.studyAction.title.localized(in: language))")

                            if let modelName = record.modelName, !modelName.isEmpty {
                                Text("\("模型：".localized(in: language))\(modelName)")
                            }

                            Text("\("状态：".localized(in: language))\(record.status.title.localized(in: language))")
                            if let statusMessage = record.statusMessage,
                               !statusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("\("说明：".localized(in: language))\(statusMessage.localized(in: language))")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: prefersCompactChrome ? .infinity : 760, alignment: .leading)
        }
        .background(
            ScrollOffsetObserver { offset in
                detailScrollOffset = offset
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .safeAreaInset(edge: .bottom) {
            if showStickyQuickCaptureChip, let onOpenInQuickCapture {
                HStack {
                    Spacer()
                    Button(language.text("快速录入", "Quick Capture")) {
                        onOpenInQuickCapture()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private var detailHeaderContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(record.content.term)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(record.correction == nil ? Color.primary : Color.red)

                if trimmedOriginalQuery != record.content.term {
                    Text(
                        language.text(
                            "（搜索：\(trimmedOriginalQuery)）",
                            "(Search: \(trimmedOriginalQuery))"
                        )
                    )
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let onQuickSaveToLibrary {
                    Button {
                        onQuickSaveToLibrary()
                    } label: {
                        Image(systemName: isInLibrary ? "star.fill" : "star")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isInLibrary ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(
                        isInLibrary
                            ? language.text("已在词库中", "Already in Library")
                            : language.text("快速加入词库", "Quick Save to Library")
                    )
                }
            }

            Text(record.content.kind.title.localized(in: language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pronunciationChrome: some View {
        if isPronounceableEnglish {
            VStack(alignment: .leading, spacing: 8) {
                pronunciationButton

                if record.content.pronunciation.isEmpty {
                    Text("简版结果暂未提供音标，你仍然可以点击上面的按钮听发音。".localized(in: language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(pronunciationLines, id: \.self) { line in
                            Text(line)
                                .font(.title3.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var pronunciationButton: some View {
        Button {
            PronunciationPlayer.shared.speak(
                record.content.term,
                displayLanguage: language,
                voicePreference: voicePreference
            )
        } label: {
            Label("播放发音".localized(in: language), systemImage: "speaker.wave.2.fill")
        }
        .buttonStyle(.bordered)
    }

    private var trimmedOriginalQuery: String {
        record.originalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPronounceableEnglish: Bool {
        let trimmed = record.content.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        return !trimmed.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private var meaningsTitle: String {
        if record.content.kind == .sentence {
            return (record.content.translationDirection?.title ?? "翻译").localized(in: language)
        }

        return "中文释义".localized(in: language)
    }

    private var examplesTitle: String {
        (record.content.kind == .sentence ? "原句与结果" : "英文例句与中文翻译").localized(in: language)
    }

    private var meaningSections: [MeaningDisplaySection] {
        DisplayFormatting.prefixedMeaningSections(
            meaningGroups: record.content.meaningGroups,
            kind: record.content.kind,
            maxLineLength: 28
        )
    }

    private var localizedInflectionLines: [String] {
        record.content.inflectionLines.map { language.localizedInflectionLine($0) }
    }

    private var localizedReferenceTags: [String] {
        record.content.referenceTags.map { language.localizedReferenceTag($0) }
    }

    private var pronunciationLines: [String] {
        let trimmed = record.content.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if let match = trimmed.range(of: #"BrE\s+(.+?),\s*AmE\s+(.+)$"#, options: .regularExpression) {
            let matched = String(trimmed[match])
            let parts = matched.replacingOccurrences(of: "BrE ", with: "").components(separatedBy: ", AmE ")
            if parts.count == 2 {
                return ["BrE  \(parts[0])", "AmE  \(parts[1])"]
            }
        }

        return [trimmed]
    }

    private var historyStatusMessage: String? {
        guard loadingMessage == nil, record.status != .completed else {
            return nil
        }

        let trimmedMessage = record.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedMessage.isEmpty else {
            return record.status.title.localized(in: language)
        }
        return "\(record.status.title.localized(in: language)) · \(trimmedMessage.localized(in: language))"
    }

    private var meaningsFallbackMessage: String {
        if let historyStatusMessage {
            return historyStatusMessage
        }

        if !record.reverseLookupCandidates.isEmpty {
            return "这次查询先给了英文候选，选中后会继续补全释义。".localized(in: language)
        }

        if record.source.primary == .fallback || record.source.components.contains(.fallback) {
            if !record.content.englishDefinitions.isEmpty {
                return "本地还没找到可靠中文释义，先给你英文释义。".localized(in: language)
            }

            return "本地词库里没有找到可靠中文释义。".localized(in: language)
        }

        return "这次结果里还没有可展示的中文释义。".localized(in: language)
    }

    private var statusForegroundStyle: AnyShapeStyle {
        switch record.status {
        case .failed:
            return AnyShapeStyle(Color.red)
        case .cancelled:
            return AnyShapeStyle(Color.orange)
        case .inProgress:
            return AnyShapeStyle(Color.secondary)
        case .completed:
            return AnyShapeStyle(Color.secondary)
        }
    }

    private var showStickyQuickCaptureChip: Bool {
        showsStickyQuickCaptureAction
            && prefersCompactChrome
            && onOpenInQuickCapture != nil
            && detailScrollOffset > 40
    }

    @ViewBuilder
    private func infoBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: prefersCompactChrome ? 8 : 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func supplementaryInfoSection<Content: View>(
        title: String,
        isInitiallyExpanded: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if prefersCompactChrome {
            SupplementaryDisclosureSection(
                title: title,
                isInitiallyExpanded: isInitiallyExpanded,
                content: content
            )
        } else {
            infoBlock(title: title, content: content)
        }
    }

    @ViewBuilder
    private func meaningRow(_ meaning: String) -> some View {
        Text(meaning)
            .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MeaningGroupsSummarySection: View {
    let title: String
    let meaningGroups: [MeaningGroup]
    let kind: EntryKind

    private var sections: [MeaningDisplaySection] {
        DisplayFormatting.prefixedMeaningSections(
            meaningGroups: meaningGroups,
            kind: kind,
            maxLineLength: 26
        )
    }

    var body: some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.lines, id: \.self) { line in
                            Text(line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }
}

private struct SimpleTextCardsSection: View {
    let title: String
    let lines: [String]
    var compact = false

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                SimpleTextCards(lines: lines, compact: compact)
            }
        }
    }
}

private struct SimpleTextCards: View {
    let lines: [String]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, compact ? 8 : 10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct ScrollOffsetObserver: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollOffsetObservingView {
        let view = ScrollOffsetObservingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScrollOffsetObservingView, context: Context) {
        nsView.onChange = onChange
        nsView.observeIfNeeded()
    }
}

private final class ScrollOffsetObservingView: NSView {
    var onChange: ((CGFloat) -> Void)?
    private var observation: NSObjectProtocol?
    private weak var observedClipView: NSClipView?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observeIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeIfNeeded()
    }

    func observeIfNeeded() {
        guard let clipView = enclosingScrollView?.contentView else {
            return
        }

        if observedClipView === clipView {
            onChange?(clipView.bounds.origin.y)
            return
        }

        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }

        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        observation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self, weak clipView] _ in
            guard let self, let clipView else {
                return
            }
            self.onChange?(clipView.bounds.origin.y)
        }
        onChange?(clipView.bounds.origin.y)
    }

    deinit {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
    }
}

private struct EnglishDefinitionPresentation {
    let primaryDefinitions: [String]
    let additionalDefinitions: [String]
    let synonyms: [String]

    init(definitions: [String], synonyms: [String], preferredVisibleCount: Int = 2) {
        var parsedDefinitions: [String] = []
        var parsedSynonyms: [String] = []

        for definition in definitions {
            let trimmed = definition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if trimmed.lowercased().hasPrefix("synonyms:") {
                let raw = trimmed.dropFirst("Synonyms:".count)
                Self.appendUniqueTerms(
                    from: String(raw)
                        .split(whereSeparator: { [",", ";", "，", "；"].contains($0) })
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) },
                    into: &parsedSynonyms
                )
                continue
            }

            let cleaned = Self.cleanDefinition(trimmed)
            guard !cleaned.isEmpty else {
                continue
            }

            if Self.containsNearDuplicate(cleaned, in: parsedDefinitions) == false {
                parsedDefinitions.append(cleaned)
            }
        }

        Self.appendUniqueTerms(from: synonyms, into: &parsedSynonyms)

        primaryDefinitions = Array(parsedDefinitions.prefix(preferredVisibleCount))
        additionalDefinitions = parsedDefinitions.count > preferredVisibleCount
            ? Array(parsedDefinitions.dropFirst(preferredVisibleCount))
            : []
        self.synonyms = parsedSynonyms
    }

    var hasContent: Bool {
        !primaryDefinitions.isEmpty || !additionalDefinitions.isEmpty || !synonyms.isEmpty
    }

    private static func cleanDefinition(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"^(?:(?:adj(?:ective)?(?:\s+satellite)?|adv(?:erb)?|noun|verb|vt|vi|v|n|a|s)\.?\s+)+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;，；"))
    }

    private static func normalizedKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsNearDuplicate(_ candidate: String, in existing: [String]) -> Bool {
        let candidateKey = normalizedKey(candidate)
        guard !candidateKey.isEmpty else {
            return true
        }

        return existing.contains { line in
            let existingKey = normalizedKey(line)
            return existingKey == candidateKey
                || existingKey.contains(candidateKey)
                || candidateKey.contains(existingKey)
        }
    }

    private static func appendUniqueTerms(from terms: [String], into target: inout [String]) {
        for term in terms {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                continue
            }

            if target.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) == false {
                target.append(cleaned)
            }
        }
    }
}

private struct EnglishDefinitionSection: View {
    let title: String
    let definitions: [String]
    let synonyms: [String]
    let language: AppDisplayLanguage
    var prefersCompactChrome = false
    @State private var showsMore = false

    private var presentation: EnglishDefinitionPresentation {
        EnglishDefinitionPresentation(definitions: definitions, synonyms: synonyms)
    }

    var body: some View {
        if presentation.hasContent {
            VStack(alignment: .leading, spacing: prefersCompactChrome ? 8 : 10) {
                Text(title)
                    .font(.headline)

                if !presentation.primaryDefinitions.isEmpty {
                    SimpleTextCards(lines: presentation.primaryDefinitions, compact: prefersCompactChrome)
                }

                if !presentation.synonyms.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("同义词".localized(in: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        SynonymPillsView(terms: presentation.synonyms)
                    }
                }

                if !presentation.additionalDefinitions.isEmpty {
                    DisclosureGroup(
                        isExpanded: $showsMore,
                        content: {
                            SimpleTextCards(lines: presentation.additionalDefinitions, compact: prefersCompactChrome)
                                .padding(.top, 8)
                        },
                        label: {
                            Text(language.text("更多英文释义", "More"))
                                .font(.subheadline.weight(.semibold))
                        }
                    )
                }
            }
        }
    }
}

private struct SynonymPillsView: View {
    let terms: [String]

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(terms, id: \.self) { term in
                Text(term)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SupplementaryDisclosureSection<Content: View>: View {
    let title: String
    let content: Content
    @State private var isExpanded: Bool

    init(
        title: String,
        isInitiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
        _isExpanded = State(initialValue: isInitiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 8)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

private struct LookupSuggestionsSection: View {
    let suggestions: [LookupSuggestion]
    let applySuggestion: (LookupSuggestion) -> Void
    var language: AppDisplayLanguage = .chinese

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地联想候选".localized(in: language))
                .font(.headline)

            ForEach(suggestions) { suggestion in
                Button {
                    applySuggestion(suggestion)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(suggestion.term)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(suggestion.reason.title.localized(in: language))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }

                            if !suggestion.preview.isEmpty {
                                Text(suggestion.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }

                        Spacer()

                        Text("继续查".localized(in: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ReverseLookupCandidateRow: View {
    let candidate: ReverseLookupCandidate
    let action: ((ReverseLookupCandidate) -> Void)?
    let onOpenInQuickCapture: ((ReverseLookupCandidate) -> Void)?
    let prefersCompactActions: Bool
    var language: AppDisplayLanguage = .chinese

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.english)
                    .font(.headline)

                Text(candidate.pinyin.isEmpty ? candidate.chinese : "\(candidate.chinese) · \(candidate.pinyin)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if prefersCompactActions {
                VStack(alignment: .trailing, spacing: 8) {
                    if let action {
                        Button("继续查这个词".localized(in: language)) {
                            action(candidate)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let onOpenInQuickCapture {
                        Button(language.text("快速录入", "Quick Capture")) {
                            onOpenInQuickCapture(candidate)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    if let action {
                        Button("继续查这个词".localized(in: language)) {
                            action(candidate)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let onOpenInQuickCapture {
                        Button(language.text("快速录入", "Quick Capture")) {
                            onOpenInQuickCapture(candidate)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FlowTagsView: View {
    let tags: [String]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryLine(for: tag))
                    if let secondaryLine = secondaryLine(for: tag) {
                        Text(secondaryLine)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, compact ? 8 : 10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func primaryLine(for tag: String) -> String {
        splitTag(tag).0
    }

    private func secondaryLine(for tag: String) -> String? {
        splitTag(tag).1
    }

    private func splitTag(_ tag: String) -> (String, String?) {
        let separator = " · "
        guard let range = tag.range(of: separator) else {
            return (tag, nil)
        }

        let primary = String(tag[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = String(tag[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (primary, secondary.isEmpty ? nil : secondary)
    }
}

private struct HistoryRow: View {
    let record: LookupHistoryRecord
    let isSelected: Bool
    var showsSelectionControl = false
    var isChecked = false
    var language: AppDisplayLanguage = .chinese
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if showsSelectionControl {
                    SelectionIndicator(isChecked: isChecked)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(record.content.term)
                            .font(.headline)
                            .foregroundStyle(record.status == .failed ? .red : .primary)
                        if record.status != .completed {
                            Text(record.status.title.localized(in: language))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusBadgeColor.opacity(0.14))
                                .foregroundStyle(statusBadgeColor)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text(record.queriedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if record.originalQuery != record.content.term {
                        Text(record.originalQuery)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(summaryColor)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        let trimmedStatusMessage = record.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if record.status != .completed {
            return trimmedStatusMessage.isEmpty
                ? record.status.title.localized(in: language)
                : trimmedStatusMessage.localized(in: language)
        }

        if !record.reverseLookupCandidates.isEmpty {
            return language.text(
                "已找到 \(record.reverseLookupCandidates.count) 个英文候选",
                "Found \(record.reverseLookupCandidates.count) English candidates"
            )
        }

        let meaningSummary = DisplayFormatting.summaryMeaning(
            meaningGroups: record.content.meaningGroups,
            kind: record.content.kind
        )
        if !meaningSummary.isEmpty {
            return meaningSummary
        }

        return record.content.kind.title.localized(in: language)
    }

    private var summaryColor: Color {
        switch record.status {
        case .failed:
            return .red
        case .cancelled:
            return .orange
        case .inProgress, .completed:
            return .secondary
        }
    }

    private var statusBadgeColor: Color {
        switch record.status {
        case .failed:
            return .red
        case .cancelled:
            return .orange
        case .inProgress:
            return .secondary
        case .completed:
            return .accentColor
        }
    }
}

private struct SavedCaptureDraftRow: View {
    let draft: CaptureDraft
    let language: AppDisplayLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.trimmedTerm.isEmpty ? "未命名草稿".localized(in: language) : draft.trimmedTerm)
                        .font(.headline)

                    if let meaning = draft.selectedMeanings.first ?? draft.meaningChoices.first {
                        Text(meaning)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MultiSelectActionBar: View {
    let isSelecting: Bool
    let selectedCount: Int
    let totalCount: Int
    let onToggleSelecting: () -> Void
    let onToggleSelectAll: () -> Void
    let onDelete: () -> Void
    var language: AppDisplayLanguage = .chinese

    var body: some View {
        HStack(spacing: 8) {
            Button((isSelecting ? "取消" : "多选").localized(in: language)) {
                onToggleSelecting()
            }
            .buttonStyle(.bordered)

            if isSelecting {
                Button((selectedCount == totalCount && totalCount > 0 ? "取消全选" : "全选").localized(in: language)) {
                    onToggleSelectAll()
                }
                .buttonStyle(.bordered)
                .disabled(totalCount == 0)

                Button("删除已选".localized(in: language)) {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(selectedCount == 0)

                Spacer()

                Text("\("已选 ".localized(in: language))\(selectedCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SelectionIndicator: View {
    let isChecked: Bool

    var body: some View {
        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isChecked ? Color.accentColor : .secondary)
    }
}

private struct LiquidGlassPanelBackground: View {
    let cornerRadius: CGFloat
    var tint: Color? = nil
    var gradientOpacity: Double = 0.18
    var shadowOpacity: Double = 0.10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedTint = tint ?? Color.accentColor.opacity(0.12)

        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(gradientOpacity * 1.22),
                            resolvedTint.opacity(0.20),
                            Color.white.opacity(gradientOpacity * 0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.36),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: cornerRadius * 3.8
                    )
                )
                .frame(width: cornerRadius * 5.2, height: cornerRadius * 4.2)
                .offset(x: -cornerRadius * 0.95, y: -cornerRadius * 1.05)
                .blur(radius: 14)
                .mask(shape)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            resolvedTint.opacity(0.22),
                            resolvedTint.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: cornerRadius * 4.4
                    )
                )
                .frame(width: cornerRadius * 5.6, height: cornerRadius * 5.6)
                .offset(x: cornerRadius * 1.05, y: cornerRadius * 1.2)
                .blur(radius: 18)
                .mask(shape)

            if #available(macOS 26.0, *) {
                shape
                    .fill(Color.white.opacity(0.001))
                    .glassEffect(Glass.regular.tint(resolvedTint), in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.white.opacity(0.20),
                            resolvedTint.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            shape
                .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                .blur(radius: 2)
                .offset(y: 1.5)
        }
        .shadow(color: Color.white.opacity(0.08), radius: 8, y: -2)
        .shadow(color: Color.black.opacity(shadowOpacity), radius: 12, y: 7)
    }
}

private enum LiquidGlassButtonDensity {
    case compact
    case regular
}

private struct LiquidGlassContentButtonModifier: ViewModifier {
    let isProminent: Bool
    var tint: Color? = nil
    var density: LiquidGlassButtonDensity = .regular

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .buttonStyle(
                LiquidGlassButtonStyle(
                    isProminent: isProminent,
                    tint: tint,
                    density: density
                )
            )
    }
}

private struct LiquidGlassButtonStyle: ButtonStyle {
    let isProminent: Bool
    var tint: Color? = nil
    var density: LiquidGlassButtonDensity = .regular

    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassButtonStyleBody(
            configuration: configuration,
            isProminent: isProminent,
            tint: tint,
            density: density
        )
    }
}

private struct LiquidGlassButtonStyleBody: View {
    let configuration: LiquidGlassButtonStyle.Configuration
    let isProminent: Bool
    var tint: Color? = nil
    var density: LiquidGlassButtonDensity = .regular

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let resolvedTint = tint ?? (isProminent ? Color.accentColor.opacity(0.20) : Color.white.opacity(0.10))
        let horizontalPadding: CGFloat = density == .compact ? (isProminent ? 13 : 11) : (isProminent ? 16 : 14)
        let verticalPadding: CGFloat = density == .compact ? 6 : 8
        let shadowOpacity: Double = density == .compact ? 0.05 : 0.07

        configuration.label
            .font(density == .compact ? .callout.weight(.semibold) : .body.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                LiquidGlassCapsuleBackground(
                    tint: resolvedTint,
                    gradientOpacity: density == .compact ? (isProminent ? 0.20 : 0.16) : (isProminent ? 0.24 : 0.18),
                    shadowOpacity: configuration.isPressed ? 0.02 : shadowOpacity,
                    density: density
                )
            }
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.spring(response: 0.20, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private struct LiquidGlassCapsuleBackground: View {
    var tint: Color
    var gradientOpacity: Double = 0.22
    var shadowOpacity: Double = 0.08
    var density: LiquidGlassButtonDensity = .regular

    var body: some View {
        let shape = Capsule()
        let highlightWidth: CGFloat = density == .compact ? 76 : 104
        let highlightHeight: CGFloat = density == .compact ? 36 : 52
        let tintWidth: CGFloat = density == .compact ? 84 : 114
        let tintHeight: CGFloat = density == .compact ? 40 : 58

        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(gradientOpacity * 1.18),
                            tint.opacity(0.20),
                            Color.white.opacity(gradientOpacity * 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: density == .compact ? 32 : 42
                    )
                )
                .frame(width: highlightWidth, height: highlightHeight)
                .offset(x: density == .compact ? -18 : -24, y: density == .compact ? -8 : -10)
                .blur(radius: density == .compact ? 8 : 10)
                .mask(shape)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.18),
                            tint.opacity(0.07),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: density == .compact ? 34 : 46
                    )
                )
                .frame(width: tintWidth, height: tintHeight)
                .offset(x: density == .compact ? 18 : 24, y: density == .compact ? 8 : 12)
                .blur(radius: density == .compact ? 10 : 14)
                .mask(shape)

            if #available(macOS 26.0, *) {
                shape
                    .fill(Color.white.opacity(0.001))
                    .glassEffect(Glass.regular.tint(tint), in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.white.opacity(0.18),
                            tint.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.white.opacity(0.06), radius: density == .compact ? 4 : 6, y: -1)
        .shadow(color: Color.black.opacity(shadowOpacity), radius: density == .compact ? 6 : 10, y: density == .compact ? 3 : 5)
    }
}

private struct SidebarRow: View {
    let section: SidebarSection
    let count: Int
    let isSelected: Bool
    let language: AppDisplayLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    LiquidGlassPanelBackground(
                        cornerRadius: 16,
                        tint: Color.accentColor.opacity(0.16),
                        gradientOpacity: 0.30,
                        shadowOpacity: 0.05
                    )
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.clear)
                }

                HStack(spacing: 12) {
                    Label(section.title.localized(in: language), systemImage: section.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 18, weight: .semibold))

                    Spacer(minLength: 8)

                    if count > 0 {
                        Text("\(count)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .foregroundStyle(Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(Color.black.opacity(0.001))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SidebarBrandHeader: View {
    let language: AppDisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SparrowWord")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .tracking(0.2)

            Text(language.text("你的词汇收集与复习空间", "Your word capture and review space"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct ReviewSessionConfiguratorSheet: View {
    let itemCount: Int
    @Binding var selectedQuestionTypes: Set<ReviewQuestionType>
    let onStart: () -> Void
    let onCancel: () -> Void

    private var orderedSelection: [ReviewQuestionType] {
        ReviewQuestionType.allCases.filter { selectedQuestionTypes.contains($0) }
    }

    private var configuration: ReviewSessionConfiguration {
        ReviewSessionConfiguration(questionTypes: orderedSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("这一轮怎么练？")
                    .font(.title2.weight(.bold))

                Text("勾一个就是固定刷，勾多个就会随机混刷。翻卡点一下屏幕就能翻面，填空和选择题会按答对升级、答错降级。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(ReviewQuestionType.allCases) { questionType in
                    ReviewQuestionTypeOptionCard(
                        questionType: questionType,
                        isSelected: selectedQuestionTypes.contains(questionType)
                    ) {
                        if selectedQuestionTypes.contains(questionType) {
                            selectedQuestionTypes.remove(questionType)
                        } else {
                            selectedQuestionTypes.insert(questionType)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    orderedSelection.isEmpty
                        ? "已选题型：请至少勾一种"
                        : "已选题型：\(orderedSelection.map(\.title).joined(separator: "、"))"
                )
                    .font(.headline)

                Text(configuration.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .opacity(orderedSelection.isEmpty ? 0.6 : 1)

            Spacer()

            HStack {
                Text("这一轮会复习 \(itemCount) 个词")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("开始复习") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .disabled(orderedSelection.isEmpty)
            }
        }
        .padding(24)
    }
}

private struct ReviewQuestionTypeOptionCard: View {
    let questionType: ReviewQuestionType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(questionType.title)
                        .font(.headline)

                    Text(questionType.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewPickerItem: Identifiable, Equatable {
    let id: UUID
    let dedupeKey: String
    let entry: VocabEntry
    let backingEntryID: UUID?
    var sourceKinds: [ReviewSourceKind]

    var orderedSourceKinds: [ReviewSourceKind] {
        ReviewSourceKind.allCases.filter { sourceKinds.contains($0) }
    }

    var sourceSummary: String {
        orderedSourceKinds.map(\.title).joined(separator: " · ")
    }

    var meaningSummary: String {
        DisplayFormatting.prefixedMeaning(
            entry.preferredMeaning,
            partOfSpeech: entry.preferredMeaningPartOfSpeech,
            kind: entry.kind
        )
    }

    var isHistoryOnly: Bool {
        backingEntryID == nil
    }
}

private struct ReviewSessionFeedback: Identifiable, Equatable {
    let id: UUID
    let message: String
    let tint: Color

    static func make(for decision: ReviewDecision) -> ReviewSessionFeedback {
        switch decision {
        case .downgrade:
            return ReviewSessionFeedback(
                id: UUID(),
                message: "知道哪里不稳，本身就是进步。",
                tint: .red
            )
        case .keep:
            return ReviewSessionFeedback(
                id: UUID(),
                message: "节奏很稳，继续这样刷。",
                tint: .yellow
            )
        case .upgrade:
            return ReviewSessionFeedback(
                id: UUID(),
                message: "漂亮，这个词你拿住了。",
                tint: .green
            )
        }
    }
}

private struct ReviewSourceChip: View {
    let source: ReviewSourceKind
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: source.systemImage)
                Text(source.shortTitle)
                    .fontWeight(.semibold)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.24) : Color(nsColor: .windowBackgroundColor))
                    )
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewSourcePill: View {
    let source: ReviewSourceKind

    var body: some View {
        Label(source.shortTitle, systemImage: source.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch source {
        case .library:
            return .indigo.opacity(0.14)
        case .favorites:
            return .pink.opacity(0.16)
        case .history:
            return .gray.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch source {
        case .favorites:
            return .pink
        case .history:
            return .secondary
        default:
            return .primary
        }
    }
}

private struct ReviewLevelPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct ReviewSelectionActionBar: View {
    let isSelecting: Bool
    let selectedCount: Int
    let totalCount: Int
    let onToggleSelecting: () -> Void
    let onToggleSelectAll: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(isSelecting ? "取消多选" : "多选") {
                onToggleSelecting()
            }
            .buttonStyle(.bordered)

            if isSelecting {
                Button(selectedCount == totalCount && totalCount > 0 ? "取消全选" : "全选") {
                    onToggleSelectAll()
                }
                .buttonStyle(.bordered)
                .disabled(totalCount == 0)

                if selectedCount > 0 {
                    Button("清空已选") {
                        onClearSelection()
                    }
                    .buttonStyle(.bordered)
                }

                Text("已选 \(selectedCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReviewEmptySelectionState: View {
    let hasSelectedSources: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(hasSelectedSources ? "当前筛选下没有可复习的词" : "先打开至少一个来源")
                .font(.title3.weight(.semibold))

            Text(
                hasSelectedSources
                    ? "你可以换个来源、排序，或者把“彻底掌握”选项改掉。上面的来源选择不会消失。"
                    : "词库、收藏和历史都可以单独开关；全关时这里只是暂时为空，不会把选择区一起弄没。"
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .padding(32)
    }
}

private struct ReviewPickerRow: View {
    let item: ReviewPickerItem
    let isSelected: Bool
    var showsSelectionControl = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if showsSelectionControl {
                    SelectionIndicator(isChecked: isSelected)
                        .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.entry.term)
                            .font(.headline)

                        if item.entry.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.pink)
                        }

                        if item.isHistoryOnly {
                            ReviewLevelPill(text: "仅历史", tint: .gray)
                        } else {
                            ReviewLevelPill(
                                text: item.entry.proficiency.title,
                                tint: proficiencyTint(item.entry.proficiency)
                            )
                        }

                        Spacer()
                    }

                    HStack(spacing: 6) {
                        ForEach(item.orderedSourceKinds) { source in
                            ReviewSourcePill(source: source)
                        }
                    }

                    Text(item.meaningSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if !item.entry.sourceContext.isEmpty {
                        Text(item.entry.sourceContext)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func proficiencyTint(_ level: ProficiencyLevel) -> Color {
        switch level {
        case .unknown:
            return .red
        case .shaky:
            return .orange
        case .familiar:
            return .yellow
        case .comfortable:
            return .green
        case .mastered:
            return .mint
        }
    }
}

private struct ReviewHistoryRound: Identifiable, Equatable {
    let id: String
    let startedAt: Date
    let finishedAt: Date
    let firstRecord: ReviewHistoryRecord
    let records: [ReviewHistoryRecord]
    let sourceKinds: [ReviewSourceKind]

    init(id: String, records: [ReviewHistoryRecord]) {
        let orderedRecords = records.sorted {
            if $0.reviewedAt == $1.reviewedAt {
                return $0.id.uuidString < $1.id.uuidString
            }

            return $0.reviewedAt < $1.reviewedAt
        }
        let firstRecord = orderedRecords.first ?? records[0]
        let lastRecord = orderedRecords.last ?? firstRecord
        let sourceSet = Set(orderedRecords.flatMap(\.sourceKinds))

        self.id = id
        self.startedAt = firstRecord.reviewSessionStartedAt ?? firstRecord.reviewedAt
        self.finishedAt = lastRecord.reviewedAt
        self.firstRecord = firstRecord
        self.records = orderedRecords
        self.sourceKinds = ReviewSourceKind.allCases.filter { sourceSet.contains($0) }
    }

    var sourceSummary: String {
        let titles = sourceKinds.map(\.shortTitle)
        return titles.isEmpty ? "未标记来源" : titles.joined(separator: " / ")
    }
}

private struct ReviewHistoryPanel: View {
    let history: [ReviewHistoryRecord]
    @State private var selectedRoundID: String?

    private var rounds: [ReviewHistoryRound] {
        let groupedHistory = Dictionary(grouping: history) { record in
            if let reviewSessionID = record.reviewSessionID {
                return "session:\(reviewSessionID.uuidString)"
            }

            if let reviewSessionStartedAt = record.reviewSessionStartedAt {
                return "started:\(Int(reviewSessionStartedAt.timeIntervalSince1970))"
            }

            return "legacy:\(Int(record.reviewedAt.timeIntervalSince1970 / 180))"
        }

        return groupedHistory
            .map { ReviewHistoryRound(id: $0.key, records: $0.value) }
            .sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.id > $1.id
                }

                return $0.startedAt > $1.startedAt
            }
    }

    private var selectedRound: ReviewHistoryRound? {
        rounds.first(where: { $0.id == selectedRoundID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("答题历史")
                    .font(.title3.weight(.semibold))

                Text("先按轮看时间、来源和第一个词，点进某一轮再看里面每一道题。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if history.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有答题记录")
                        .font(.headline)
                    Text("完成一整轮或哪怕只做完一题，这里都会按轮记下来。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let selectedRound {
                ReviewHistoryRoundDetailView(round: selectedRound) {
                    selectedRoundID = nil
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(rounds) { round in
                            ReviewHistoryRoundRow(round: round) {
                                selectedRoundID = round.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onChange(of: rounds.map(\.id)) { _, roundIDs in
            guard let selectedRoundID, roundIDs.contains(selectedRoundID) == false else {
                return
            }

            self.selectedRoundID = nil
        }
        .padding(24)
        .padding(.vertical, 28)
        .padding(.trailing, 28)
    }
}

private struct ReviewHistoryRoundRow: View {
    let round: ReviewHistoryRound
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(round.firstRecord.term)
                        .font(.headline)
                        .lineLimit(1)

                    Text(round.sourceSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(round.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewHistoryRoundDetailView: View {
    let round: ReviewHistoryRound
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) {
                Label("返回所有轮次", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("这一轮从 \(round.firstRecord.term) 开始")
                    .font(.headline)

                Text(round.sourceSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(round.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("共 \(round.records.count) 题，下面是这一轮里的具体作答。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(round.records.enumerated()), id: \.element.id) { offset, record in
                        ReviewHistoryRow(record: record, index: offset + 1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ReviewHistoryRow: View {
    let record: ReviewHistoryRecord
    var index: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if let index {
                    ReviewLevelPill(text: "第 \(index) 题", tint: .accentColor)
                }

                Text(record.term)
                    .font(.headline)

                Text(record.decision.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(decisionTint.opacity(0.14))
                    .foregroundStyle(decisionTint)
                    .clipShape(Capsule())

                Spacer()
            }

            Text(record.meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(levelText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Text(record.reviewedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(record.sourceKinds.map(\.shortTitle).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var decisionTint: Color {
        switch record.decision {
        case .downgrade:
            return .red
        case .keep:
            return .yellow
        case .upgrade:
            return .green
        }
    }

    private var levelText: String {
        if let previous = record.previousProficiency, let resulting = record.resultingProficiency {
            return "\(previous.title) -> \(resulting.title) · \(record.mode.title)"
        }

        return "未改动词库熟练度 · \(record.mode.title)"
    }
}

private struct ReviewFeedbackBanner: View {
    let feedback: ReviewSessionFeedback

    var body: some View {
        Text(feedback.message)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(feedback.tint.gradient)
            )
            .shadow(color: feedback.tint.opacity(0.3), radius: 18, y: 10)
    }
}

private struct ReviewDecisionActionButton: View {
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .opacity(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewCardView: View {
    private enum AnswerOutcome {
        case correct
        case incorrect

        var title: String {
            switch self {
            case .correct:
                return "判定正确"
            case .incorrect:
                return "判定错误"
            }
        }

        var detail: String {
            switch self {
            case .correct:
                return "会按自动规则升级。"
            case .incorrect:
                return "会按自动规则降级。"
            }
        }

        var tint: Color {
            switch self {
            case .correct:
                return .green
            case .incorrect:
                return .red
            }
        }
    }

    let card: ReviewCard
    let entry: VocabEntry
    let progressText: String
    let sessionStyleTitle: String
    let sessionStyleDetail: String
    let sourceSummary: String
    let showsHistoryOnlyHint: Bool
    @Binding var draft: ReviewAnswerDraft
    let onPreviousCard: () -> Void
    let onNextCard: () -> Void
    let onAdvanceWithDefaultDecision: () -> Void
    let onDecision: (ReviewDecision) -> Void
    let onEndSession: () -> Void

    @FocusState private var isTypedAnswerFieldFocused: Bool

    private var isFlashcardMode: Bool {
        card.isFlashcardMode
    }

    private var canSubmitAnswer: Bool {
        switch card.mode {
        case .multipleChoice:
            return draft.selectedChoice.isEmpty == false
        case .meaningToTerm, .termToMeaning:
            return draft.typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .flashcardTermToMeaning, .flashcardMeaningToTerm:
            return true
        }
    }

    private var submittedAnswerText: String {
        switch card.mode {
        case .multipleChoice:
            return draft.selectedChoice
        case .meaningToTerm, .termToMeaning:
            return draft.typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        case .flashcardTermToMeaning, .flashcardMeaningToTerm:
            return ""
        }
    }

    private var submitButtonTitle: String {
        isFlashcardMode ? "翻开答案" : "提交作答"
    }

    private var answerOutcome: AnswerOutcome? {
        guard draft.answerSubmitted else {
            return nil
        }

        switch card.mode {
        case .multipleChoice:
            return draft.selectedChoice == card.answer ? .correct : .incorrect
        case .meaningToTerm, .termToMeaning:
            return card.matchesSubmittedAnswer(draft.typedAnswer) ? .correct : .incorrect
        case .flashcardTermToMeaning, .flashcardMeaningToTerm:
            return nil
        }
    }

    private var autoDecision: ReviewDecision {
        switch card.questionType {
        case .flashcards:
            return .upgrade
        case .multipleChoice, .fillIn:
            return answerOutcome == .correct ? .upgrade : .downgrade
        }
    }

    private var autoAdvanceButtonTitle: String {
        "下一题 · 默认\(autoDecision.title)"
    }

    private var autoDecisionCaption: String {
        if showsHistoryOnlyHint {
            return "这张卡来自历史记录，只会记录这次答题，不会改动词库熟练度。"
        }

        switch card.questionType {
        case .flashcards:
            return "翻卡模式默认升级；如果你想保守一点，可以手动改成保持或降级。"
        case .multipleChoice, .fillIn:
            if let answerOutcome {
                return answerOutcome.detail + " 如果你想覆写熟练度，再手动点下面三个按钮。"
            }

            return "如果不手动改熟练度，系统会按答对升级、答错降级。"
        }
    }

    private var canNavigateBetweenCards: Bool {
        draft.answerSubmitted || card.questionType != .fillIn || isTypedAnswerFieldFocused == false
    }

    private var canAdvanceWithReturn: Bool {
        draft.answerSubmitted
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isFlashcardMode, draft.answerSubmitted == false {
                            submitAnswer()
                        }
                    }

                VStack(spacing: 18) {
                    HStack {
                        Button("结束本轮") {
                            onEndSession()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text("第 \(progressText) 张")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 960)

                    Spacer(minLength: 0)

                    VStack(spacing: draft.answerSubmitted ? 18 : 24) {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                ReviewLevelPill(text: card.promptTitle, tint: .accentColor)
                                ReviewLevelPill(text: sessionStyleTitle, tint: .blue)

                                if showsHistoryOnlyHint {
                                    ReviewLevelPill(text: "历史记录", tint: .gray)
                                } else {
                                    ReviewLevelPill(text: entry.proficiency.title, tint: proficiencyTint(entry.proficiency))
                                }
                            }

                            Text(sourceSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text(sessionStyleDetail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text(card.prompt)
                                .font(.system(size: promptFontSize(for: proxy.size.height), weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 820)

                            Text(entry.reviewPromptHint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)

                        if card.mode == .multipleChoice {
                            VStack(spacing: 10) {
                                ForEach(card.distractors, id: \.self) { option in
                                    Button {
                                        guard !draft.answerSubmitted else { return }
                                        draft.selectedChoice = option
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: selectionSymbol(for: option))
                                                .font(.title3)

                                            Text(option)
                                                .font(.title3.weight(.semibold))
                                                .multilineTextAlignment(.center)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 16)
                                        .frame(maxWidth: .infinity)
                                        .background(optionBackground(for: option))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(optionBorder(for: option), lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(draft.answerSubmitted)
                                }
                            }
                            .frame(maxWidth: 760)
                        } else if isFlashcardMode {
                            VStack(spacing: 12) {
                                VStack(spacing: 10) {
                                    Text("先在脑中回忆，再轻点一下屏幕翻卡。")
                                        .font(.headline)

                                    Text("不用按按钮；点空白处、卡面都可以翻开答案。")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 28)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                )
                            }
                            .frame(maxWidth: 680)
                        } else {
                            VStack(spacing: 12) {
                                TextField("先自己作答，再看参考答案", text: $draft.typedAnswer)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.title3)
                                    .multilineTextAlignment(.center)
                                    .focused($isTypedAnswerFieldFocused)
                                    .onSubmit {
                                        submitAnswer()
                                    }

                                Text("填空会按你词库里选中的答案来判定；像 apple / apples 这种词形对得上也算对。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: 680)
                        }

                        if draft.answerSubmitted {
                            answerPanel
                        }
                    }
                    .frame(maxWidth: 960)

                    Spacer(minLength: 0)

                    if draft.answerSubmitted {
                        VStack(spacing: 16) {
                            Button(autoAdvanceButtonTitle) {
                                onDecision(autoDecision)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Text(autoDecisionCaption)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 760)

                            HStack(spacing: 16) {
                                ReviewDecisionActionButton(
                                    title: "降级",
                                    subtitle: "覆盖自动结果",
                                    tint: .red
                                ) {
                                    onDecision(.downgrade)
                                }

                                ReviewDecisionActionButton(
                                    title: "保持",
                                    subtitle: "覆盖自动结果",
                                    tint: .yellow
                                ) {
                                    onDecision(.keep)
                                }

                                ReviewDecisionActionButton(
                                    title: "升级",
                                    subtitle: "覆盖自动结果",
                                    tint: .green
                                ) {
                                    onDecision(.upgrade)
                                }
                            }
                        }
                        .frame(maxWidth: 920)
                    } else if !isFlashcardMode {
                        Button(submitButtonTitle) {
                            submitAnswer()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canSubmitAnswer)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(width: proxy.size.width, height: proxy.size.height)

                ReviewKeyboardShortcutCapture(
                    canFlipFlashcard: isFlashcardMode && draft.answerSubmitted == false,
                    canAdvanceWithReturn: canAdvanceWithReturn,
                    canNavigate: canNavigateBetweenCards,
                    onFlipFlashcard: submitAnswer,
                    onAdvanceWithReturn: onAdvanceWithDefaultDecision,
                    onPreviousCard: onPreviousCard,
                    onNextCard: onNextCard
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .id("\(card.entryID.uuidString)-\(card.mode.rawValue)")
    }

    @ViewBuilder
    private var answerPanel: some View {
        VStack(spacing: 10) {
            Text(isFlashcardMode ? "卡背答案" : "参考答案")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let answerOutcome {
                ReviewLevelPill(text: answerOutcome.title, tint: answerOutcome.tint)
            }

            Text(card.answer)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            if !submittedAnswerText.isEmpty {
                Text("你的作答：\(submittedAnswerText)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(answerOutcome?.tint ?? .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let example = entry.selectedGeneratedExample {
                Text(example)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if !entry.sourceContext.isEmpty {
                Text(entry.sourceContext)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if showsHistoryOnlyHint {
                Text("这张卡来自历史记录，答完不会改动词库熟练度。")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func submitAnswer() {
        guard canSubmitAnswer else {
            return
        }

        isTypedAnswerFieldFocused = false
        draft.answerSubmitted = true
    }

    private func selectionSymbol(for option: String) -> String {
        if draft.answerSubmitted {
            if option == card.answer {
                return "checkmark.circle.fill"
            }

            if option == draft.selectedChoice {
                return "xmark.circle.fill"
            }
        }

        return draft.selectedChoice == option ? "checkmark.circle.fill" : "circle"
    }

    private func optionBackground(for option: String) -> Color {
        if draft.answerSubmitted {
            if option == card.answer {
                return .green.opacity(0.14)
            }

            if option == draft.selectedChoice {
                return .red.opacity(0.12)
            }
        }

        if draft.selectedChoice == option {
            return Color.accentColor.opacity(0.14)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private func optionBorder(for option: String) -> Color {
        if draft.answerSubmitted {
            if option == card.answer {
                return .green.opacity(0.45)
            }

            if option == draft.selectedChoice {
                return .red.opacity(0.4)
            }
        }

        if draft.selectedChoice == option {
            return Color.accentColor.opacity(0.35)
        }

        return Color(nsColor: .separatorColor)
    }

    private func promptFontSize(for height: CGFloat) -> CGFloat {
        if draft.answerSubmitted {
            return height < 760 ? 34 : 38
        }

        return height < 760 ? 36 : 42
    }

    private func proficiencyTint(_ level: ProficiencyLevel) -> Color {
        switch level {
        case .unknown:
            return .red
        case .shaky:
            return .orange
        case .familiar:
            return .yellow
        case .comfortable:
            return .green
        case .mastered:
            return .mint
        }
    }
}

private struct ReviewKeyboardShortcutCapture: View {
    let canFlipFlashcard: Bool
    let canAdvanceWithReturn: Bool
    let canNavigate: Bool
    let onFlipFlashcard: () -> Void
    let onAdvanceWithReturn: () -> Void
    let onPreviousCard: () -> Void
    let onNextCard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if canFlipFlashcard {
                Button("") {
                    onFlipFlashcard()
                }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }

            if canAdvanceWithReturn {
                Button("") {
                    onAdvanceWithReturn()
                }
                .keyboardShortcut(.return, modifiers: [])
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }

            if canNavigate {
                Button("") {
                    onPreviousCard()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }

            if canNavigate {
                Button("") {
                    onNextCard()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct EntryRow: View {
    let entry: VocabEntry
    var language: AppDisplayLanguage = .chinese

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.term)
                    .font(.headline)

                if entry.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }

                Spacer()
                Text(entry.proficiency.title.localized(in: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(
                DisplayFormatting.prefixedMeaning(
                    entry.preferredMeaning,
                    partOfSpeech: entry.preferredMeaningPartOfSpeech,
                    kind: entry.kind
                )
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct EntryListButtonRow: View {
    let entry: VocabEntry
    let isSelected: Bool
    var showsSelectionControl = false
    var isChecked = false
    var language: AppDisplayLanguage = .chinese
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if showsSelectionControl {
                    SelectionIndicator(isChecked: isChecked)
                        .padding(.top, 4)
                }

                EntryRow(entry: entry, language: language)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SavedArrangementEntryDropDelegate: DropDelegate {
    let targetEntryID: UUID
    @Binding var draggingEntryID: UUID?
    let arrangementID: UUID?
    let appState: AppState

    func dropEntered(info: DropInfo) {
        guard let arrangementID,
              let draggingEntryID,
              draggingEntryID != targetEntryID else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            appState.moveEntry(draggingEntryID, inSavedArrangement: arrangementID, to: targetEntryID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingEntryID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        arrangementID != nil && draggingEntryID != nil
    }
}

private struct EmptyStateView: View {
    let title: String
    let subtitle: String
    var language: AppDisplayLanguage = .chinese

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.localized(in: language))
                .font(.title2.weight(.semibold))
            Text(subtitle.localized(in: language))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
    }
}
