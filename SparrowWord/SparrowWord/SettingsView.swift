import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    @State private var activePanel: SettingsPanel = .general
    @State private var searchText = ""
    @State private var excludeMasteredFromReviewDraft: Bool
    @State private var interfaceLanguageDraft: AppInterfaceLanguage
    @State private var pronunciationVoicePreferenceDraft: PronunciationVoicePreference
    @State private var workspacePaneLayoutPreferenceDraft: WorkspacePaneLayoutPreference
    @State private var showLookupReferenceTagsDraft: Bool
    @State private var isAIGenerationEnabledDraft: Bool
    @State private var openAIModelDraft: String
    @State private var openAIAPIKeyDraft: String
    @State private var trashFilter: TrashFilter = .all
    @State private var trashSort: TrashSortOption = .deletedNewest
    @State private var isSelectingTrash = false
    @State private var selectedTrashIDs: Set<UUID> = []
    @State private var isDragSelectingTrash = false
    @State private var ignoreNextTapAfterDrag = false
    @State private var marqueeStartPoint: CGPoint?
    @State private var marqueeCurrentPoint: CGPoint?
    @State private var marqueeBaseSelection: Set<UUID> = []
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var scrollViewportFrame: CGRect = .zero
    @State private var resolvedScrollView: NSScrollView?
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var showingClearAPIKeyConfirmation = false
    @State private var showingEmptyTrashConfirmation = false
    @State private var showingPermanentDeleteConfirmation = false
    @State private var pendingPermanentDeleteIDs: Set<UUID> = []
    @State private var pendingPermanentDeleteLabel = ""

    private let panelOrder: [SettingsPanel] = [.general, .study, .resources, .recovery]
    private let selectionSpaceName = "TrashMarqueeSelectionSpace"

    init(appState: AppState) {
        self.appState = appState
        _excludeMasteredFromReviewDraft = State(initialValue: appState.settings.excludeMasteredFromReview)
        _interfaceLanguageDraft = State(initialValue: appState.settings.interfaceLanguage)
        _pronunciationVoicePreferenceDraft = State(initialValue: appState.settings.pronunciationVoicePreference)
        _workspacePaneLayoutPreferenceDraft = State(initialValue: appState.settings.workspacePaneLayoutPreference)
        _showLookupReferenceTagsDraft = State(initialValue: appState.settings.showLookupReferenceTags)
        _isAIGenerationEnabledDraft = State(initialValue: appState.settings.isAIGenerationEnabled)
        _openAIModelDraft = State(initialValue: appState.settings.openAIModel)
        _openAIAPIKeyDraft = State(initialValue: appState.openAIAPIKey)
    }

    private var draftSettings: AppSettings {
        var updated = appState.settings
        updated.excludeMasteredFromReview = excludeMasteredFromReviewDraft
        updated.interfaceLanguage = interfaceLanguageDraft
        updated.pronunciationVoicePreference = pronunciationVoicePreferenceDraft
        updated.workspacePaneLayoutPreference = workspacePaneLayoutPreferenceDraft
        updated.showLookupReferenceTags = showLookupReferenceTagsDraft
        updated.isAIGenerationEnabled = isAIGenerationEnabledDraft
        updated.openAIModel = openAIModelDraft
        return updated
    }

    private var displayLanguage: AppDisplayLanguage {
        interfaceLanguageDraft.resolvedLanguage()
    }

    private var openAIAPIKeyStatusText: String {
        let trimmedDraft = openAIAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStored = appState.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedDraft.isEmpty {
            return appState.isOpenAIAPIKeyStored ? "当前 Keychain 里有 key，保存后会清除。" : "还没有保存到 Keychain。"
        }

        if trimmedDraft == trimmedStored, appState.isOpenAIAPIKeyStored {
            return appState.openAIAPIKeyStorageStatusText
        }

        return "待保存到 Keychain。"
    }

    private var openAIAPIKeyStatusColor: Color {
        let trimmedDraft = openAIAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStored = appState.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDraft == trimmedStored && appState.isOpenAIAPIKeyStored ? .green : .secondary
    }

    private var visibleTrashItems: [TrashItem] {
        let filtered = appState.trashItems.filter { item in
            switch trashFilter {
            case .all:
                return true
            case .captureDraft:
                return item.sourceCategory == .captureDraft
            case .library:
                return item.sourceCategory == .library
            case .history:
                return item.sourceCategory == .history
            }
        }

        switch trashSort {
        case .deletedNewest:
            return filtered.sorted { $0.deletedAt > $1.deletedAt }
        case .deletedOldest:
            return filtered.sorted { $0.deletedAt < $1.deletedAt }
        case .termAscending:
            return filtered.sorted {
                let left = $0.term.localizedLowercase
                let right = $1.term.localizedLowercase
                if left == right {
                    return $0.deletedAt > $1.deletedAt
                }
                return left < right
            }
        case .sourceCategory:
            return filtered.sorted {
                if $0.sourceCategory == $1.sourceCategory {
                    return $0.deletedAt > $1.deletedAt
                }
                return $0.sourceCategory.rawValue < $1.sourceCategory.rawValue
            }
        }
    }

    private var activeMarqueeRect: CGRect? {
        guard let marqueeStartPoint, let marqueeCurrentPoint, isDragSelectingTrash else {
            return nil
        }
        return marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private var visiblePanels: [SettingsPanel] {
        if normalizedSearchText.isEmpty {
            return panelOrder
        }

        return panelOrder.filter { $0.matches(searchText: normalizedSearchText) }
    }

    private var isFilteringSettings: Bool {
        normalizedSearchText.isEmpty == false
    }

    var body: some View {
        HSplitView {
            settingsSidebar

            VStack(spacing: 0) {
                if visiblePanels.isEmpty {
                    emptySearchResults
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            activePanelContent
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button(displayLanguage.text("取消", "Cancel")) {
                        dismiss()
                    }
                    Button(displayLanguage.text("保存", "Save")) {
                        appState.settings = draftSettings
                        appState.openAIAPIKey = openAIAPIKeyDraft
                        appState.persistSettings()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 920, minHeight: 760)
        .onChange(of: searchText) { _, _ in
            guard let firstVisiblePanel = visiblePanels.first,
                  visiblePanels.contains(activePanel) == false else {
                return
            }
            activePanel = firstVisiblePanel
        }
        .onChange(of: visibleTrashItems.map(\.id)) { _, visibleIDs in
            let validIDs = Set(visibleIDs)
            selectedTrashIDs.formIntersection(validIDs)
            if isSelectingTrash, validIDs.isEmpty {
                isSelectingTrash = false
            }
            if !isSelectingTrash {
                isDragSelectingTrash = false
            }
        }
        .onDisappear {
            stopAutoScroll()
        }
        .alert(displayLanguage.text("清空 API key？", "Clear API key?"), isPresented: $showingClearAPIKeyConfirmation) {
            Button(displayLanguage.text("取消", "Cancel"), role: .cancel) {}
            Button(displayLanguage.text("清空", "Clear"), role: .destructive) {
                openAIAPIKeyDraft = ""
            }
        } message: {
            Text(displayLanguage.text("保存后会把当前输入的 API key 从 Keychain 里移除。", "Saving will remove the current API key from Keychain."))
        }
        .alert(displayLanguage.text("清空回收站？", "Empty Trash?"), isPresented: $showingEmptyTrashConfirmation) {
            Button(displayLanguage.text("取消", "Cancel"), role: .cancel) {}
            Button(displayLanguage.text("清空", "Empty"), role: .destructive) {
                appState.emptyTrash()
            }
        } message: {
            Text(displayLanguage.text("这会永久删除回收站里的所有项目，不能撤销。", "This permanently deletes every item in Trash and cannot be undone."))
        }
        .alert(
            displayLanguage.text("彻底删除这些项目？", "Permanently delete these items?"),
            isPresented: $showingPermanentDeleteConfirmation
        ) {
            Button(displayLanguage.text("取消", "Cancel"), role: .cancel) {
                pendingPermanentDeleteIDs.removeAll()
                pendingPermanentDeleteLabel = ""
            }
            Button(displayLanguage.text("删除", "Delete"), role: .destructive) {
                appState.permanentlyDeleteTrashItems(pendingPermanentDeleteIDs)
                pendingPermanentDeleteIDs.removeAll()
                pendingPermanentDeleteLabel = ""
                selectedTrashIDs.removeAll()
                isSelectingTrash = false
                resetMarqueeSelection()
            }
        } message: {
            Text(
                pendingPermanentDeleteLabel.isEmpty
                    ? displayLanguage.text("这些项目会被永久删除，不能恢复。", "These items will be deleted forever and cannot be restored.")
                    : pendingPermanentDeleteLabel
            )
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayLanguage.text("设置", "Settings"))
                    .font(.title2.weight(.semibold))
                Text(displayLanguage.text("把偏好、资源和恢复操作分开放。", "Separate preferences, resources, and recovery tools."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField(displayLanguage.text("搜索设置", "Search settings"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visiblePanels) { panel in
                        Button {
                            activePanel = panel
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(panel.title(for: displayLanguage))
                                    .font(.headline)
                                Text(panel.subtitle(for: displayLanguage))
                                    .font(.caption)
                                    .foregroundStyle(activePanel == panel ? Color.white.opacity(0.9) : .secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(activePanel == panel ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            )
                            .foregroundStyle(activePanel == panel ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptySearchResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayLanguage.text("没有匹配的设置", "No matching settings"))
                .font(.title2.weight(.semibold))
            Text(displayLanguage.text("试试搜索 layout、review、dictionary、backup 或 voice。", "Try searching for layout, review, dictionary, backup, or voice."))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private func settingsSectionMatches(_ keywords: [String]) -> Bool {
        if normalizedSearchText.isEmpty {
            return true
        }

        return keywords.contains { keyword in
            keyword.localizedLowercase.contains(normalizedSearchText)
        }
    }

    private func settingsSectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func settingsPickerRow<SelectionValue: Hashable, Content: View>(
        title: String,
        subtitle: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Picker(title, selection: selection) {
                    content()
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var activePanelContent: some View {
        switch activePanel {
        case .general:
            if settingsSectionMatches(["general", "language", "voice", "layout", "界面", "发音", "布局"]) {
                settingsSectionCard(
                    title: displayLanguage.text("界面与发音", "Interface & Voice"),
                    subtitle: displayLanguage.text(
                        "放每天会碰到的偏好：语言、发音和主工作区布局。",
                        "Keep everyday preferences here: language, pronunciation, and the main workspace layout."
                    )
                ) {
                    settingsPickerRow(
                        title: displayLanguage.text("软件语言", "Interface Language"),
                        subtitle: displayLanguage.text("决定设置页和主界面的语言。", "Controls the language used across settings and the main workspace."),
                        selection: $interfaceLanguageDraft
                    ) {
                        ForEach(AppInterfaceLanguage.allCases) { language in
                            Text(language.title(for: displayLanguage)).tag(language)
                        }
                    }

                    settingsPickerRow(
                        title: displayLanguage.text("发音语音", "Pronunciation Voice"),
                        subtitle: displayLanguage.text("决定朗读词条时使用哪一个系统语音。", "Choose which system voice is used when reading terms aloud."),
                        selection: $pronunciationVoicePreferenceDraft
                    ) {
                        ForEach(PronunciationVoicePreference.allCases) { preference in
                            Text(preference.title(for: displayLanguage)).tag(preference)
                        }
                    }

                    settingsPickerRow(
                        title: displayLanguage.text("主工作区布局", "Main Workspace Layout"),
                        subtitle: displayLanguage.text("自动模式会在窗口变窄时改成上下布局。", "Automatic switches to a top-and-bottom layout when the window gets narrow."),
                        selection: $workspacePaneLayoutPreferenceDraft
                    ) {
                        ForEach(WorkspacePaneLayoutPreference.allCases) { preference in
                            Text(preference.title(for: displayLanguage)).tag(preference)
                        }
                    }

                    settingsToggleRow(
                        title: displayLanguage.text("显示词频 / 词典标签", "Show frequency and dictionary tags"),
                        subtitle: displayLanguage.text(
                            "默认关闭，只有你明确想看时才在查词详情里显示这些标签。",
                            "Off by default. Lookup details only show these tags when you explicitly want them."
                        ),
                        isOn: $showLookupReferenceTagsDraft
                    )
                }
            }

        case .study:
            if settingsSectionMatches(["study", "review", "mastered", "复习", "学习"]) {
                settingsSectionCard(
                    title: displayLanguage.text("复习默认行为", "Review Defaults"),
                    subtitle: displayLanguage.text(
                        "这里只放学习策略，不混杂数据维护和技术配置。",
                        "Keep learning strategy here without mixing in maintenance or technical configuration."
                    )
                ) {
                    settingsToggleRow(
                        title: displayLanguage.text("默认不复习“彻底掌握”词汇", "Exclude mastered terms by default"),
                        subtitle: displayLanguage.text("开启后，默认复习轮次会跳过已经彻底掌握的词。", "When enabled, review rounds skip terms you already marked as mastered."),
                        isOn: $excludeMasteredFromReviewDraft
                    )
                }
            }

        case .resources:
            if settingsSectionMatches(["ai", "api", "model", "openai", "资源", "词典", "dictionary", "offline", "sentence"]) {
                settingsSectionCard(
                    title: "AI / API".localized(in: displayLanguage),
                    subtitle: displayLanguage.text(
                        "AI 和本地词典都属于资源配置，不应该跟常规偏好混在一起。",
                        "AI and offline dictionaries are resource configuration, not everyday preferences."
                    )
                ) {
                Toggle("启用 OpenAI 生成候选".localized(in: displayLanguage), isOn: $isAIGenerationEnabledDraft)

                SecureField("API key", text: $openAIAPIKeyDraft)
                    .textFieldStyle(.roundedBorder)

                LabeledContent("API key 状态".localized(in: displayLanguage)) {
                    Text(openAIAPIKeyStatusText.localized(in: displayLanguage))
                        .foregroundStyle(openAIAPIKeyStatusColor)
                }

                TextField("模型名称".localized(in: displayLanguage), text: $openAIModelDraft)
                    .textFieldStyle(.roundedBorder)

                Text("API key 会保存在 macOS Keychain，不会写入 settings.json。".localized(in: displayLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("未配置 key、关闭 AI，或请求失败时，会自动回退到本地生成。".localized(in: displayLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("测试 OpenAI".localized(in: displayLanguage)) {
                        appState.testOpenAIConfiguration(
                            settingsOverride: draftSettings,
                            apiKeyOverride: openAIAPIKeyDraft
                        )
                    }
                    .disabled(appState.isTestingOpenAI)

                    if appState.isTestingOpenAI {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()
                }

                if !appState.openAITestMessage.isEmpty {
                    Text(appState.openAITestMessage.localized(in: displayLanguage))
                        .font(.footnote)
                        .foregroundStyle(appState.didLastOpenAITestSucceed ? Color.green : Color.secondary)
                        .textSelection(.enabled)
                }
                }
            }

            if settingsSectionMatches(["dictionary", "offline", "sentence", "词典", "资源", "本地"]) {
                settingsSectionCard(
                    title: "本地词典".localized(in: displayLanguage),
                    subtitle: displayLanguage.text(
                        "这里专门放离线资源和句子引擎状态。",
                        "Keep offline resources and sentence-engine status in one technical place."
                    )
                ) {
                LabeledContent("默认目录".localized(in: displayLanguage)) {
                    Text(appState.defaultOfflineDictionaryFolderPath)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent("导入状态".localized(in: displayLanguage)) {
                    Text(appState.offlineResourcesStatusText.localized(in: displayLanguage))
                        .foregroundStyle(appState.settings.offlineResources.isImported ? Color.green : Color.secondary)
                }

                LabeledContent("句子引擎".localized(in: displayLanguage)) {
                    Text(appState.sentenceEngineStatusText.localized(in: displayLanguage))
                        .foregroundStyle(appState.sentenceEngineStatusColor)
                }

                Text(appState.sentenceEngineDisplayMessage.localized(in: displayLanguage))
                    .font(.footnote)
                    .foregroundStyle(appState.sentenceEngineMessageColor)
                    .textSelection(.enabled)

                if !appState.offlineResourceStatusMessage.isEmpty {
                    Text(appState.offlineResourceStatusMessage.localized(in: displayLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let importedAt = appState.settings.offlineResources.importedAt {
                    Text("\(displayLanguage.text("最近导入：", "Last Imported:"))\(importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !appState.settings.offlineResources.resourcesDirectoryPath.isEmpty {
                    Text("\(displayLanguage.text("资源目录：", "Resources Directory:"))\(appState.settings.offlineResources.resourcesDirectoryPath)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 12) {
                    Button("导入桌面“本地词典”".localized(in: displayLanguage)) {
                        chooseOfflineDictionaryFolder(initialURL: URL(fileURLWithPath: appState.defaultOfflineDictionaryFolderPath, isDirectory: true))
                    }
                    .disabled(appState.isImportingOfflineResources)

                    Button("选择文件夹导入".localized(in: displayLanguage)) {
                        chooseOfflineDictionaryFolder(initialURL: nil)
                    }
                    .disabled(appState.isImportingOfflineResources)

                    if appState.isImportingOfflineResources {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("导入后会把词典复制到 app 自己的本地目录，并建立 ECDICT / CEDICT / Tatoeba / Argos 所需索引。".localized(in: displayLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

        case .recovery:
            if settingsSectionMatches(["data", "recovery", "folder", "storage", "backup", "路径", "数据", "恢复"]) {
                settingsSectionCard(
                    title: displayLanguage.text("数据与恢复", "Data & Recovery"),
                    subtitle: displayLanguage.text(
                        "把数据目录、恢复入口和维护工具隔离出来，避免干扰日常偏好设置。",
                        "Isolate data paths, recovery entry points, and maintenance tools from everyday preferences."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本地数据目录".localized(in: displayLanguage))
                            .font(.headline)
                        Text(appState.storagePathDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Button(displayLanguage.text("在 Finder 中显示", "Reveal in Finder")) {
                            revealInFinder(path: appState.storagePathDescription)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if settingsSectionMatches(["trash", "delete", "restore", "回收站", "删除", "恢复"]) {
                settingsSectionCard(
                    title: "回收站".localized(in: displayLanguage),
                    subtitle: displayLanguage.text(
                        "已删除项目集中放在这里，避免和正常偏好混在一起。",
                        "Deleted items stay here so recovery tools do not mix with normal preferences."
                    )
                ) {
                Text("词库整理和 Quick Capture 草稿整理现在都在各自页面里调。这里专门放已删除项目，避免和日常操作混在一起。".localized(in: displayLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Picker("分类".localized(in: displayLanguage), selection: $trashFilter) {
                        ForEach(TrashFilter.allCases) { filter in
                            Text(filter.title.localized(in: displayLanguage)).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("排序".localized(in: displayLanguage), selection: $trashSort) {
                        ForEach(TrashSortOption.allCases) { option in
                            Text(option.title.localized(in: displayLanguage)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 8) {
                    Button((isSelectingTrash ? "取消" : "多选").localized(in: displayLanguage)) {
                        toggleTrashSelectionMode()
                    }

                    if isSelectingTrash {
                        Button("恢复已选".localized(in: displayLanguage)) {
                            restoreSelectedTrashItems()
                        }
                        .disabled(selectedTrashIDs.isEmpty)

                        Button((selectedTrashIDs == Set(visibleTrashItems.map(\.id)) && !visibleTrashItems.isEmpty ? "取消全选" : "全选").localized(in: displayLanguage)) {
                            toggleSelectAllTrash()
                        }
                        .disabled(visibleTrashItems.isEmpty)

                        Button("删除已选".localized(in: displayLanguage), role: .destructive) {
                            schedulePermanentDelete(
                                itemIDs: selectedTrashIDs,
                                label: displayLanguage.text(
                                    "已选的 \(selectedTrashIDs.count) 个项目会被永久删除，不能恢复。",
                                    "The \(selectedTrashIDs.count) selected items will be deleted forever and cannot be restored."
                                )
                            )
                        }
                        .disabled(selectedTrashIDs.isEmpty)

                        Spacer()

                        Text("\(displayLanguage.text("已选 ", "Selected "))\(selectedTrashIDs.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(displayLanguage.text("批量清空放在下方危险操作区。", "Bulk empty lives in the danger zone below."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if visibleTrashItems.isEmpty {
                    Text((appState.trashItems.isEmpty ? "回收站还是空的。" : "这个分类下暂时没有内容。").localized(in: displayLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(visibleTrashItems) { item in
                                TrashRow(
                                    item: item,
                                    showsSelectionControl: isSelectingTrash,
                                    isChecked: selectedTrashIDs.contains(item.id),
                                    onSelect: {
                                        if ignoreNextTapAfterDrag {
                                            return
                                        }

                                        if isSelectingTrash {
                                            toggleTrashSelection(for: item.id)
                                        }
                                    },
                                    onRestore: {
                                        appState.restoreTrashItems([item.id])
                                    },
                                    onDelete: {
                                        schedulePermanentDelete(
                                            itemIDs: [item.id],
                                            label: displayLanguage.text(
                                                "“\(item.term.isEmpty ? "未命名项目" : item.term)” 会被永久删除，不能恢复。",
                                                "\"\(item.term.isEmpty ? "Untitled Item" : item.term)\" will be deleted forever and cannot be restored."
                                            )
                                        )
                                    }
                                )
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
                    .frame(minHeight: 360, maxHeight: 560)
                }
                }
            }

            if settingsSectionMatches(["danger", "destructive", "api key", "clear", "empty trash", "危险"]) {
                settingsSectionCard(
                    title: displayLanguage.text("危险操作", "Danger Zone"),
                    subtitle: displayLanguage.text(
                        "这里的操作会清空或永久删除数据，需要额外确认。",
                        "Actions here clear or permanently delete data and always require confirmation."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(displayLanguage.text("清空 API key", "Clear API key"), role: .destructive) {
                            showingClearAPIKeyConfirmation = true
                        }
                        .disabled(openAIAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isOpenAIAPIKeyStored)

                        Button(displayLanguage.text("清空回收站", "Empty Trash"), role: .destructive) {
                            showingEmptyTrashConfirmation = true
                        }
                        .disabled(appState.trashItems.isEmpty)
                    }
                }
            }
        }
    }

    private func toggleTrashSelectionMode() {
        isSelectingTrash.toggle()
        resetMarqueeSelection()
        if !isSelectingTrash {
            selectedTrashIDs.removeAll()
        }
    }

    private func toggleTrashSelection(for itemID: UUID) {
        if selectedTrashIDs.contains(itemID) {
            selectedTrashIDs.remove(itemID)
        } else {
            selectedTrashIDs.insert(itemID)
        }
    }

    private func toggleSelectAllTrash() {
        let visibleIDs = Set(visibleTrashItems.map(\.id))
        if !visibleIDs.isEmpty, selectedTrashIDs == visibleIDs {
            selectedTrashIDs.removeAll()
        } else {
            selectedTrashIDs = visibleIDs
        }
    }

    private func deleteSelectedTrashItems() {
        let itemIDs = selectedTrashIDs
        guard !itemIDs.isEmpty else {
            return
        }

        schedulePermanentDelete(
            itemIDs: itemIDs,
            label: displayLanguage.text(
                "已选的 \(itemIDs.count) 个项目会被永久删除，不能恢复。",
                "The \(itemIDs.count) selected items will be deleted forever and cannot be restored."
            )
        )
    }

    private func restoreSelectedTrashItems() {
        let itemIDs = selectedTrashIDs
        guard !itemIDs.isEmpty else {
            return
        }

        appState.restoreTrashItems(itemIDs)
        selectedTrashIDs.removeAll()
        isSelectingTrash = false
        resetMarqueeSelection()
    }

    private func updateMarqueeSelection(start: CGPoint, current: CGPoint) {
        if !isDragSelectingTrash {
            marqueeBaseSelection = isSelectingTrash ? selectedTrashIDs : []
            if !isSelectingTrash {
                isSelectingTrash = true
                selectedTrashIDs.removeAll()
                marqueeBaseSelection.removeAll()
            }
        }

        isDragSelectingTrash = true
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
        guard isDragSelectingTrash,
              let marqueeStartPoint,
              let marqueeCurrentPoint else {
            return
        }

        let rect = marqueeSelectionRect(from: marqueeStartPoint, to: marqueeCurrentPoint)
        let intersectedIDs = Set<UUID>(visibleTrashItems.compactMap { item in
            guard let frame = rowFrames[item.id], frame.intersects(rect) else {
                return nil
            }
            return item.id
        })

        selectedTrashIDs = marqueeBaseSelection.union(intersectedIDs)
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
                guard isDragSelectingTrash, let resolvedScrollView else {
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
        isDragSelectingTrash = false
        marqueeStartPoint = nil
        marqueeCurrentPoint = nil
        marqueeBaseSelection.removeAll()
        DispatchQueue.main.async {
            ignoreNextTapAfterDrag = false
        }
    }

    private func chooseOfflineDictionaryFolder(initialURL: URL?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = displayLanguage.text("导入", "Import")
        panel.directoryURL = initialURL ?? URL(fileURLWithPath: appState.defaultOfflineDictionaryFolderPath, isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            appState.importOfflineResources(from: url)
        }
    }

    private func revealInFinder(path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: trimmedPath)])
    }

    private func schedulePermanentDelete(itemIDs: Set<UUID>, label: String) {
        guard !itemIDs.isEmpty else {
            return
        }

        pendingPermanentDeleteIDs = itemIDs
        pendingPermanentDeleteLabel = label
        showingPermanentDeleteConfirmation = true
    }
}

private enum SettingsPanel: String, CaseIterable, Identifiable {
    case general
    case study
    case resources
    case recovery

    var id: String { rawValue }

    func title(for language: AppDisplayLanguage) -> String {
        switch self {
        case .general:
            return language.text("常规", "General")
        case .study:
            return language.text("学习", "Study")
        case .resources:
            return language.text("资源与 AI", "Resources & AI")
        case .recovery:
            return language.text("数据与恢复", "Data & Recovery")
        }
    }

    func subtitle(for language: AppDisplayLanguage) -> String {
        switch self {
        case .general:
            return language.text("语言、发音、布局", "Language, voice, layout")
        case .study:
            return language.text("复习默认行为", "Review defaults")
        case .resources:
            return language.text("本地词典和 OpenAI", "Offline dictionaries and OpenAI")
        case .recovery:
            return language.text("回收站、数据目录、危险操作", "Trash, data folder, dangerous actions")
        }
    }

    func matches(searchText: String) -> Bool {
        let tokens: [String]
        switch self {
        case .general:
            tokens = ["general", "language", "voice", "layout", "常规", "语言", "发音", "布局"]
        case .study:
            tokens = ["study", "review", "mastered", "学习", "复习"]
        case .resources:
            tokens = ["resource", "resources", "ai", "api", "dictionary", "offline", "sentence", "资源", "词典", "本地"]
        case .recovery:
            tokens = ["recovery", "trash", "backup", "folder", "data", "danger", "恢复", "回收站", "数据", "危险"]
        }

        return tokens.contains { $0.localizedLowercase.contains(searchText) }
    }
}

private enum TrashFilter: String, CaseIterable, Identifiable {
    case all
    case captureDraft
    case library
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .captureDraft:
            return "Quick Capture 草稿删除"
        case .library:
            return "词库删除"
        case .history:
            return "历史删除"
        }
    }
}

private enum TrashSortOption: String, CaseIterable, Identifiable {
    case deletedNewest
    case deletedOldest
    case termAscending
    case sourceCategory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deletedNewest:
            return "按删除时间倒序"
        case .deletedOldest:
            return "按删除时间正序"
        case .termAscending:
            return "按英文 A-Z"
        case .sourceCategory:
            return "按分类"
        }
    }
}

private struct TrashRow: View {
    let item: TrashItem
    let showsSelectionControl: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsSelectionControl {
                Button(action: onSelect) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChecked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.term.isEmpty ? "未命名项目" : item.term)
                        .font(.headline)

                    Spacer()

                    Text(item.sourceCategory.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !item.detailText.isEmpty {
                    Text(item.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if !item.metadataText.isEmpty {
                        Text(item.metadataText)
                    }

                    Text(item.deletedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !showsSelectionControl {
                HStack(spacing: 10) {
                    Button("恢复") {
                        onRestore()
                    }
                    .buttonStyle(.borderless)

                    Button("彻底删除", role: .destructive) {
                        onDelete()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if showsSelectionControl {
                onSelect()
            }
        }
    }
}

struct EntrySortRulesEditor: View {
    @ObservedObject var appState: AppState
    @State private var draggingCriterion: EntrySortCriterion?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("直接拖动卡片上下调整优先级。双击某一行，可以切换这一项的正序 / 倒序。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(Array(appState.settings.entrySortRules.enumerated()), id: \.element.id) { index, rule in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.criterion.title)
                                .font(.body.weight(.medium))
                            Text(rule.direction.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("#\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor(for: rule.criterion), lineWidth: draggingCriterion == rule.criterion ? 2 : 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(draggingCriterion == rule.criterion ? 0.75 : 1)
                    .onTapGesture(count: 2) {
                        appState.toggleSortRuleDirection(rule.criterion)
                    }
                    .onDrag {
                        draggingCriterion = rule.criterion
                        return NSItemProvider(object: rule.criterion.rawValue as NSString)
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: EntrySortRuleDropDelegate(
                            targetCriterion: rule.criterion,
                            draggingCriterion: $draggingCriterion,
                            appState: appState
                        )
                    )
                }
            }
        }
    }

    private func borderColor(for criterion: EntrySortCriterion) -> Color {
        if draggingCriterion == criterion {
            return .accentColor
        }

        return Color(nsColor: .separatorColor)
    }
}

private struct EntrySortRuleDropDelegate: DropDelegate {
    let targetCriterion: EntrySortCriterion
    @Binding var draggingCriterion: EntrySortCriterion?
    let appState: AppState

    func dropEntered(info: DropInfo) {
        guard let draggingCriterion, draggingCriterion != targetCriterion else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            appState.moveSortRule(draggingCriterion, to: targetCriterion)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingCriterion = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingCriterion != nil
    }
}
