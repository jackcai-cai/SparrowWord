import Foundation

enum AppDisplayLanguage: String, Sendable {
    case chinese
    case english

    func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .chinese:
            return chinese
        case .english:
            return english
        }
    }

    func localized(_ text: String) -> String {
        switch self {
        case .chinese:
            return LocalizationCatalog.englishToChinese[text] ?? text
        case .english:
            return LocalizationCatalog.chineseToEnglish[text] ?? text
        }
    }

    func localizedInflectionLine(_ text: String) -> String {
        guard self == .english else {
            return text
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return text
        }

        let replacements: [(String, String)] = [
            ("原形：", "Base form: "),
            ("当前词形：", "Current form: "),
            ("第三人称单数：", "Third-person singular: "),
            ("现在分词：", "Present participle: "),
            ("过去式 / 过去分词：", "Past tense / past participle: "),
            ("过去式：", "Past tense: "),
            ("过去分词：", "Past participle: "),
            ("复数：", "Plural: "),
            ("比较级：", "Comparative: "),
            ("最高级：", "Superlative: ")
        ]

        for (prefix, replacement) in replacements where trimmed.hasPrefix(prefix) {
            return replacement + String(trimmed.dropFirst(prefix.count))
        }

        return text
    }

    func localizedReferenceTag(_ text: String) -> String {
        guard self == .english else {
            return text
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return text
        }

        if let regex = try? NSRegularExpression(pattern: #"^柯林斯\s+(\d+)\s+星$"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
           let scoreRange = Range(match.range(at: 1), in: trimmed) {
            return "Collins \(trimmed[scoreRange])"
        }

        let exactMappings: [String: String] = [
            "牛津核心词": "Oxford Core",
            "中考": "Zhongkao",
            "高考": "Gaokao",
            "四级": "CET-4",
            "六级": "CET-6",
            "考研": "Postgrad Exam"
        ]

        if let exactMatch = exactMappings[trimmed] {
            return exactMatch
        }

        if let regex = try? NSRegularExpression(pattern: #"^现代词频\s+#(\d+)$"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
           let scoreRange = Range(match.range(at: 1), in: trimmed) {
            return "Frequency #\(trimmed[scoreRange])"
        }

        return text
    }
}

enum AppInterfaceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    func resolvedLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppDisplayLanguage {
        switch self {
        case .chinese:
            return .chinese
        case .english:
            return .english
        case .system:
            let preferredLanguage = preferredLanguages.first?.lowercased() ?? ""
            return preferredLanguage.hasPrefix("zh") ? .chinese : .english
        }
    }

    func title(for displayLanguage: AppDisplayLanguage) -> String {
        switch self {
        case .system:
            return displayLanguage.text("跟随系统", "Follow System")
        case .chinese:
            return displayLanguage.text("简体中文", "Simplified Chinese")
        case .english:
            return "English"
        }
    }
}

enum PronunciationVoicePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case chinese
    case english

    var id: String { rawValue }

    func title(for displayLanguage: AppDisplayLanguage) -> String {
        switch self {
        case .automatic:
            return displayLanguage.text("跟随文本自动选择", "Auto Detect from Text")
        case .chinese:
            return displayLanguage.text("中文系统语音", "Chinese System Voice")
        case .english:
            return displayLanguage.text("英文系统语音", "English System Voice")
        }
    }
}

extension String {
    func localized(in language: AppDisplayLanguage) -> String {
        language.localized(self)
    }
}

private enum LocalizationCatalog {
    static let chineseToEnglish: [String: String] = [
        "查词": "Lookup",
        "收集箱": "Study Drafts",
        "词库": "Library",
        "复习": "Review",
        "历史": "History",
        "单词": "Word",
        "词组": "Phrase",
        "句子": "Sentence",
        "快速录入": "Quick Capture",
        "设置": "Settings",
        "这里可以查单词、词组和句子。结果会先记录到历史；需要继续学习时，再显式送去 Quick Capture 或词库。中文单词/词组会先给英文候选，句子会走本地离线翻译。": "Look up words, phrases, and sentences here. Results land in History first; when you want to keep studying, send them explicitly to Quick Capture or Library. Chinese words and phrases show English candidates first. Sentences use the local offline engine.",
        "类型": "Type",
        "输入要查的单词，也可以直接输中文反查英文": "Type an English word, or enter Chinese to reverse-look up English",
        "输入要查的词组，也可以直接输中文反查英文": "Type an English phrase, or enter Chinese to reverse-look up English",
        "输入英文或中文句子": "Type an English or Chinese sentence",
        "你遇到它时的原句 / 上下文": "Original sentence / context",
        "查词时会把这段原句一起带进结果和后续的 Quick Capture / 词库保存；你在等待结果时补录，也会跟上这次查询。": "This context stays with the lookup result and with any later Quick Capture or Library save. If you add it while the result is still loading, it still attaches to this lookup.",
        "已自动纠正：": "Auto-corrected:",
        "正在查词...": "Looking up...",
        "正在按纠正后的拼写继续查词...": "Continuing with the corrected spelling...",
        "还没有查词结果": "No lookup result yet",
        "输入英文、中文或句子先拿结果；要继续学习时，再显式送去 Quick Capture 或词库。": "Type English, Chinese, or a sentence to get the result first. When you want to keep studying, send it explicitly to Quick Capture or Library.",
        "正在查询": "Looking up",
        "正在处理“": "Processing “",
        "”，请稍等一下。": "”. Please wait a moment.",
        "这次查询失败了": "This lookup failed",
        "本地联想候选": "Local suggestions",
        "句子引擎": "Sentence Engine",
        "播放发音": "Play Audio",
        "自动纠正：": "Auto-correction:",
        "中文释义": "Chinese Meaning",
        "英文释义": "English Definition",
        "英文例句与中文翻译": "English Examples / Chinese Translations",
        "这次查词记录": "Lookup Record",
        "原句与结果": "Original Sentence / Result",
        "本地离线资源已导入。": "Offline resources have been imported.",
        "还没有导入本地离线词典。": "Offline dictionaries have not been imported yet.",
        "本地句子翻译引擎已就绪。": "The local sentence translation engine is ready.",
        "句子翻译引擎会在首次查句子时自动准备。": "The local sentence translation engine will prepare itself the first time you look up a sentence.",
        "导入本地词典后，句子翻译才会可用。": "Sentence translation becomes available after local dictionary resources are imported.",
        "正在准备本地句子翻译引擎...": "Preparing the local sentence translation engine...",
        "本地句子翻译引擎暂时不可用。": "The local sentence translation engine is temporarily unavailable.",
        "软件语言": "Interface Language",
        "发音语音": "Pronunciation Voice",
        "默认不复习“彻底掌握”词汇": "Exclude “Mastered” words from review by default",
        "本地数据目录": "Local Data Directory",
        "取消": "Cancel",
        "保存": "Save",
        "AI / API": "AI / API",
        "本地词典": "Offline Dictionaries",
        "回收站": "Trash",
        "API key 状态": "API Key Status",
        "待保存到 Keychain。": "Ready to save to Keychain.",
        "还没有保存到 Keychain。": "Not saved to Keychain yet.",
        "当前 Keychain 里有 key，保存后会清除。": "A key is currently stored in Keychain. Saving will clear it.",
        "模型名称": "Model Name",
        "API key 会保存在 macOS Keychain，不会写入 settings.json。": "The API key is stored in macOS Keychain and is not written to settings.json.",
        "未配置 key、关闭 AI，或请求失败时，会自动回退到本地生成。": "If the key is missing, AI is off, or the request fails, SparrowWord will fall back to local generation.",
        "测试 OpenAI": "Test OpenAI",
        "清空 API key": "Clear API Key",
        "默认目录": "Default Directory",
        "导入状态": "Import Status",
        "最近导入：": "Last Imported:",
        "资源目录：": "Resources Directory:",
        "导入桌面“本地词典”": "Import Desktop “Local Dictionaries”",
        "选择文件夹导入": "Choose Folder to Import",
        "导入后会把词典复制到 app 自己的本地目录，并建立 ECDICT / CEDICT / Tatoeba / Argos 所需索引。": "Imported resources are copied into the app's local directory and indexed for ECDICT / CEDICT / Tatoeba / Argos.",
        "词库整理和 Quick Capture 草稿整理现在都在各自页面里调。这里专门放已删除项目，避免和日常操作混在一起。": "Library organization and Quick Capture draft organization now live on their own pages. Trash stays here so deleted items do not mix with daily work.",
        "分类": "Category",
        "排序": "Sort",
        "全部": "All",
        "Quick Capture 草稿删除": "Deleted Quick Capture Draft",
        "词库删除": "Deleted from Library",
        "历史删除": "Deleted from History",
        "按删除时间倒序": "Deleted Time Descending",
        "按删除时间正序": "Deleted Time Ascending",
        "按英文 A-Z": "English A-Z",
        "按分类": "By Category",
        "多选": "Multi-select",
        "恢复已选": "Restore Selected",
        "取消全选": "Clear Selection",
        "全选": "Select All",
        "删除已选": "Delete Selected",
        "已选 ": "Selected ",
        "清空回收站": "Empty Trash",
        "回收站还是空的。": "Trash is still empty.",
        "这个分类下暂时没有内容。": "There is no content in this category yet.",
        "恢复": "Restore",
        "彻底删除": "Delete Permanently",
        "未命名项目": "Untitled Item",
        "选择一个词条": "Choose an entry",
        "你可以在这里二选一挑释义和例句，再决定是否放进词库。": "Pick meanings and example sentences here before deciding whether to move the entry into your library.",
        "词库还没有条目": "Library is still empty",
        "把词条正式保存进词库后，它们会在这里稳定积累。": "Once you save entries into Library, they will accumulate here as stable study items.",
        "最近更新": "Recently Updated",
        "最早更新": "Oldest Updated",
        "最近录入": "Recently Added",
        "英文 A-Z": "English A-Z",
        "词性：": "Part of speech:",
        "收藏": "Favorite",
        "已收藏": "Favorited",
        "熟练度": "Familiarity",
        "按词性整理": "Meanings by Part of Speech",
        "中文释义候选": "Chinese Meaning Candidates",
        "系统例句候选": "Example Sentence Candidates",
        "你遇到它时的原句": "Original sentence",
        "录入于 ": "Added on ",
        "备注": "Notes",
        "生成状态": "Generation Status",
        "最近时间：暂无": "Latest time: None",
        "当前：": "Current:",
        "正在生成": "Generating",
        "空闲": "Idle",
        "最近来源：": "Latest source:",
        "触发方式：": "Trigger:",
        "模型：": "Model:",
        "原因：": "Reason:",
        "刷新候选": "Refresh Candidates",
        "合并 ": "Merge ",
        " 个重复词条": " duplicate entries",
        "删除": "Delete",
        "删除词条": "Delete Entry",
        "确认进入词库": "Confirm into Library",
        "添加候选": "Add Candidate",
        "最多添加 ": "Add up to ",
        " 个候选": " candidates",
        "删除当前勾选的候选框": "Delete the currently selected candidates",
        "至少选择一个候选。": "Select at least one candidate.",
        "查询状态": "Lookup Status",
        "当前结果不提供发音。": "This result does not provide pronunciation.",
        "简版结果暂未提供音标，你仍然可以点击上面的按钮听发音。": "This compact result does not include phonetics yet, but you can still use the button above to hear it.",
        "原始查询": "Original Query",
        "正在加载中文释义...": "Loading Chinese meanings...",
        "英文候选": "English Candidates",
        "词形变化 / 词形关系": "Inflections / Word Forms",
        "词频 / 词典标签": "Frequency / Dictionary Tags",
        "正在补充例句...": "Loading example sentences...",
        "常见搭配 / 短语": "Common Collocations / Phrases",
        "正在补充常见搭配...": "Loading common collocations...",
        "这次结果里没有给出实用搭配。": "This result does not include useful collocations.",
        "时间：": "Time:",
        "来源：": "Source:",
        "学习动作：": "Study action:",
        "状态：": "Status:",
        "说明：": "Note:",
        "词形": "Inflection",
        "联想": "Suggestion",
        "短语": "Phrase",
        "继续查": "Look Up Again",
        "继续查这个词": "Look Up This Word",
        "查询中": "In Progress",
        "已完成": "Completed",
        "已取消": "Cancelled",
        "失败": "Failed",
        "系统词典": "System Dictionary",
        "本地回退": "Local Fallback",
        "已创建学习草稿": "Created study draft",
        "已更新学习草稿": "Updated study draft",
        "该词已在词库中": "Already in Library",
        "仅记录历史": "History Only",
        "等待你选择英文候选": "Waiting for English Candidate Selection",
        "词库、收藏和历史都可以单独开关；全关时这里只是暂时为空，不会把选择区一起弄没。": "Library, Favorites, and History can all be toggled independently. If you turn them all off, the view is only temporarily empty; the source controls stay visible.",
        "已载入保存的 Quick Capture 草稿。": "Loaded the saved Quick Capture draft.",
        "保存 Quick Capture 草稿失败：": "Failed to save Quick Capture draft: ",
        "这次查询先给了英文候选，选中后会继续补全释义。": "This lookup returned English candidates first. Pick one to continue filling in the meanings.",
        "本地还没找到可靠中文释义，先给你英文释义。": "No reliable Chinese meanings were found locally yet, so English definitions are shown first.",
        "本地词库里没有找到可靠中文释义。": "No reliable Chinese meanings were found in the local dictionary.",
        "这次结果里还没有可展示的中文释义。": "There are no Chinese meanings to show in this result yet.",
        "还没有查词历史": "No lookup history yet",
        "先去上面的“查词”页查几个词，这里会按时间记录下来。": "Look up a few items first. Your history will show up here in time order.",
        "按英文或中文过滤历史": "Filter history by English or Chinese",
        "选择一条历史": "Choose a history entry",
        "这里会显示当时查到的释义、例句、翻译、搭配和发音。": "This shows the meanings, examples, translations, collocations, and pronunciation from that lookup.",
        "不认识": "Unknown",
        "不熟": "Shaky",
        "有印象": "Familiar",
        "比较熟了": "Comfortable",
        "彻底掌握": "Mastered"
    ]

    static let englishToChinese: [String: String] = Dictionary(
        chineseToEnglish.map { ($1, $0) },
        uniquingKeysWith: { first, _ in first }
    )
}
