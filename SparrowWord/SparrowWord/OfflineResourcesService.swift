import Foundation
import SQLite3

enum OfflineResourceImportError: LocalizedError {
    case missingFiles([String])
    case unreadableLine(String)
    case sqliteFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingFiles(let files):
            return "缺少这些离线资源文件：\(files.joined(separator: "、"))"
        case .unreadableLine(let line):
            return "读取离线词典时遇到无法解析的内容：\(line)"
        case .sqliteFailure(let message):
            return message
        }
    }
}

struct OfflineResourcePaths {
    let sourceDirectory: URL
    let ecdictDatabase: URL
    let cedictText: URL
    let sentencesCSV: URL
    let linksCSV: URL
    let argosEnToZh: URL
    let argosZhToEn: URL
}

nonisolated final class OfflineResourcesService {
    private let storage: StorageService
    private let fileManager = FileManager.default

    init(storage: StorageService = StorageService()) {
        self.storage = storage
    }

    func defaultSourceDirectory() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("本地词典", isDirectory: true)
    }

    /// On first launch (or whenever no ECDICT is present), seed the bundled lite
    /// ECDICT into Application Support so English word lookup works with zero manual
    /// import. Never overwrites an existing/real ECDICT (e.g. a full manual import).
    /// Returns an updated manifest if seeding happened, otherwise `nil`.
    func seedBundledECDICTIfNeeded(into manifest: OfflineResourceManifest) -> OfflineResourceManifest? {
        let ecdictDirectory = storage.offlineResourcesDirectory().appendingPathComponent("ecdict", isDirectory: true)
        let target = ecdictDirectory.appendingPathComponent("stardict.db")

        // Gate J: do not overwrite a real/existing ECDICT.
        if manifest.isECDICTReady, fileManager.fileExists(atPath: manifest.ecdictDatabasePath) {
            return nil
        }
        if fileManager.fileExists(atPath: target.path) {
            return nil
        }
        guard let bundled = Bundle.main.url(forResource: "ecdict-lite", withExtension: "sqlite") else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: ecdictDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: bundled, to: target)
        } catch {
            return nil
        }

        var updated = manifest
        updated.resourcesDirectoryPath = storage.offlineResourcesDirectory().path
        updated.ecdictDatabasePath = target.path
        updated.isECDICTReady = true
        return updated
    }

    func validateSourceDirectory(_ directory: URL) -> Result<OfflineResourcePaths, OfflineResourceImportError> {
        let paths = OfflineResourcePaths(
            sourceDirectory: directory,
            ecdictDatabase: directory.appendingPathComponent("stardict.db"),
            cedictText: directory.appendingPathComponent("cedict_1_0_ts_utf-8_mdbg.txt"),
            sentencesCSV: directory.appendingPathComponent("sentences.csv"),
            linksCSV: directory.appendingPathComponent("links.csv"),
            argosEnToZh: directory.appendingPathComponent("translate-en_zh-1_9.argosmodel"),
            argosZhToEn: directory.appendingPathComponent("translate-zh_en-1_9.argosmodel")
        )

        let missing = [
            ("stardict.db", paths.ecdictDatabase),
            ("cedict_1_0_ts_utf-8_mdbg.txt", paths.cedictText),
            ("sentences.csv", paths.sentencesCSV),
            ("links.csv", paths.linksCSV),
            ("translate-en_zh-1_9.argosmodel", paths.argosEnToZh),
            ("translate-zh_en-1_9.argosmodel", paths.argosZhToEn),
        ]
            .compactMap { name, url in
                fileManager.fileExists(atPath: url.path) ? nil : name
            }

        if missing.isEmpty {
            return .success(paths)
        }

        return .failure(.missingFiles(missing))
    }

    func importResources(from directory: URL) throws -> OfflineResourceManifest {
        let paths: OfflineResourcePaths

        switch validateSourceDirectory(directory) {
        case .success(let resolved):
            paths = resolved
        case .failure(let error):
            throw error
        }

        let resourcesDirectory = storage.offlineResourcesDirectory()
        let rawDirectory = resourcesDirectory.appendingPathComponent("raw", isDirectory: true)
        let ecdictDirectory = resourcesDirectory.appendingPathComponent("ecdict", isDirectory: true)
        let cedictDirectory = resourcesDirectory.appendingPathComponent("cedict", isDirectory: true)
        let tatoebaDirectory = resourcesDirectory.appendingPathComponent("tatoeba", isDirectory: true)
        let argosDirectory = resourcesDirectory.appendingPathComponent("argos", isDirectory: true)
        let argosPackagesDirectory = argosDirectory.appendingPathComponent("packages", isDirectory: true)

        try fileManager.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: ecdictDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cedictDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tatoebaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: argosPackagesDirectory, withIntermediateDirectories: true)

        let copiedECDICT = ecdictDirectory.appendingPathComponent("stardict.db")
        let copiedCEDICTText = rawDirectory.appendingPathComponent("cedict_1_0_ts_utf-8_mdbg.txt")
        let copiedSentencesCSV = rawDirectory.appendingPathComponent("sentences.csv")
        let copiedLinksCSV = rawDirectory.appendingPathComponent("links.csv")
        let copiedArgosEnToZh = argosPackagesDirectory.appendingPathComponent("translate-en_zh-1_9.argosmodel")
        let copiedArgosZhToEn = argosPackagesDirectory.appendingPathComponent("translate-zh_en-1_9.argosmodel")

        try replaceItem(at: copiedECDICT, with: paths.ecdictDatabase)
        try replaceItem(at: copiedCEDICTText, with: paths.cedictText)
        try replaceItem(at: copiedSentencesCSV, with: paths.sentencesCSV)
        try replaceItem(at: copiedLinksCSV, with: paths.linksCSV)
        try replaceItem(at: copiedArgosEnToZh, with: paths.argosEnToZh)
        try replaceItem(at: copiedArgosZhToEn, with: paths.argosZhToEn)

        let cedictDatabase = cedictDirectory.appendingPathComponent("cedict.sqlite")
        try buildCEDICTDatabase(from: copiedCEDICTText, outputURL: cedictDatabase)

        let tatoebaDatabase = tatoebaDirectory.appendingPathComponent("tatoeba.sqlite")
        try buildTatoebaDatabase(sentencesURL: copiedSentencesCSV, linksURL: copiedLinksCSV, outputURL: tatoebaDatabase)

        return OfflineResourceManifest(
            sourceFolderPath: directory.path,
            importedAt: .now,
            resourcesDirectoryPath: resourcesDirectory.path,
            ecdictDatabasePath: copiedECDICT.path,
            cedictDatabasePath: cedictDatabase.path,
            tatoebaDatabasePath: tatoebaDatabase.path,
            argosPackagesDirectoryPath: argosPackagesDirectory.path,
            pythonHelperDirectoryPath: storage.pythonHelperDirectory().path,
            isECDICTReady: fileManager.fileExists(atPath: copiedECDICT.path),
            isCEDICTReady: fileManager.fileExists(atPath: cedictDatabase.path),
            isTatoebaReady: fileManager.fileExists(atPath: tatoebaDatabase.path),
            sentenceEngineStatus: .unavailable,
            sentenceEngineMessage: "句子翻译引擎会在首次查句子时自动准备。",
            lexiconEnrichmentVersion: 0
        )
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func buildCEDICTDatabase(from sourceURL: URL, outputURL: URL) throws {
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let database = try SQLiteDatabase(url: outputURL)

        try database.execute("""
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE cedict_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            traditional TEXT NOT NULL,
            simplified TEXT NOT NULL,
            pinyin TEXT NOT NULL,
            english TEXT NOT NULL
        );
        """)

        let insertStatement = try database.prepare("INSERT INTO cedict_entries (traditional, simplified, pinyin, english) VALUES (?, ?, ?, ?);")
        defer { sqlite3_finalize(insertStatement) }

        try database.execute("BEGIN TRANSACTION;")

        do {
            for line in try LineSequence(url: sourceURL) {
                if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }

                guard let parsed = parseCEDICT(line: line) else {
                    continue
                }

                sqlite3_bind_text(insertStatement, 1, parsed.traditional, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStatement, 2, parsed.simplified, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStatement, 3, parsed.pinyin, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStatement, 4, parsed.english, -1, SQLITE_TRANSIENT)

                guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                    throw database.error("写入 CEDICT 失败")
                }

                sqlite3_reset(insertStatement)
                sqlite3_clear_bindings(insertStatement)
            }

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }

        try database.execute("""
        CREATE INDEX idx_cedict_simplified ON cedict_entries (simplified);
        CREATE INDEX idx_cedict_traditional ON cedict_entries (traditional);
        CREATE INDEX idx_cedict_english ON cedict_entries (english);
        """)
    }

    private func buildTatoebaDatabase(sentencesURL: URL, linksURL: URL, outputURL: URL) throws {
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let database = try SQLiteDatabase(url: outputURL)

        try database.execute("""
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE sentences (
            id INTEGER PRIMARY KEY,
            lang TEXT NOT NULL,
            text TEXT NOT NULL
        );
        CREATE TABLE raw_links (
            source_id INTEGER NOT NULL,
            target_id INTEGER NOT NULL
        );
        CREATE TABLE bilingual_links (
            eng_id INTEGER NOT NULL,
            cmn_id INTEGER NOT NULL,
            PRIMARY KEY (eng_id, cmn_id)
        );
        """)

        let sentenceInsert = try database.prepare("INSERT INTO sentences (id, lang, text) VALUES (?, ?, ?);")
        let rawLinkInsert = try database.prepare("INSERT INTO raw_links (source_id, target_id) VALUES (?, ?);")
        defer {
            sqlite3_finalize(sentenceInsert)
            sqlite3_finalize(rawLinkInsert)
        }

        try database.execute("BEGIN TRANSACTION;")

        do {
            for line in try LineSequence(url: sentencesURL) {
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 3 else {
                    continue
                }

                let lang = parts[1]
                guard lang == "eng" || lang == "cmn" else {
                    continue
                }

                guard let sentenceID = Int64(parts[0]) else {
                    continue
                }

                sqlite3_bind_int64(sentenceInsert, 1, sentenceID)
                sqlite3_bind_text(sentenceInsert, 2, lang, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(sentenceInsert, 3, parts[2], -1, SQLITE_TRANSIENT)

                guard sqlite3_step(sentenceInsert) == SQLITE_DONE else {
                    throw database.error("写入 Tatoeba sentences 失败")
                }

                sqlite3_reset(sentenceInsert)
                sqlite3_clear_bindings(sentenceInsert)
            }

            for line in try LineSequence(url: linksURL) {
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 2,
                      let sourceID = Int64(parts[0]),
                      let targetID = Int64(parts[1]) else {
                    continue
                }

                sqlite3_bind_int64(rawLinkInsert, 1, sourceID)
                sqlite3_bind_int64(rawLinkInsert, 2, targetID)

                guard sqlite3_step(rawLinkInsert) == SQLITE_DONE else {
                    throw database.error("写入 Tatoeba links 失败")
                }

                sqlite3_reset(rawLinkInsert)
                sqlite3_clear_bindings(rawLinkInsert)
            }

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }

        try database.execute("""
        INSERT OR IGNORE INTO bilingual_links (eng_id, cmn_id)
        SELECT
            CASE WHEN source.lang = 'eng' THEN source.id ELSE target.id END,
            CASE WHEN source.lang = 'cmn' THEN source.id ELSE target.id END
        FROM raw_links
        JOIN sentences AS source ON source.id = raw_links.source_id
        JOIN sentences AS target ON target.id = raw_links.target_id
        WHERE (source.lang = 'eng' AND target.lang = 'cmn')
           OR (source.lang = 'cmn' AND target.lang = 'eng');

        CREATE INDEX idx_sentences_lang ON sentences (lang);
        CREATE INDEX idx_sentences_text ON sentences (text);
        CREATE INDEX idx_bilingual_links_eng ON bilingual_links (eng_id);
        CREATE INDEX idx_bilingual_links_cmn ON bilingual_links (cmn_id);
        CREATE VIRTUAL TABLE english_sentences_fts USING fts5(text, content='sentences', content_rowid='id');
        INSERT INTO english_sentences_fts(rowid, text)
        SELECT id, text FROM sentences WHERE lang = 'eng';
        DROP TABLE raw_links;
        """)
    }

    private func parseCEDICT(line: String) -> (traditional: String, simplified: String, pinyin: String, english: String)? {
        guard let pinyinStart = line.firstIndex(of: "["),
              let pinyinEnd = line.firstIndex(of: "]"),
              pinyinStart < pinyinEnd else {
            return nil
        }

        let headwords = line[..<pinyinStart].trimmingCharacters(in: .whitespaces)
        let pinyin = line[line.index(after: pinyinStart)..<pinyinEnd].trimmingCharacters(in: .whitespaces)
        let englishPortion = line[line.index(after: pinyinEnd)...].trimmingCharacters(in: .whitespaces)
        let components = headwords.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

        guard components.count == 2 else {
            return nil
        }

        let english = englishPortion
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !english.isEmpty else {
            return nil
        }

        return (
            traditional: String(components[0]),
            simplified: String(components[1]),
            pinyin: pinyin,
            english: english
        )
    }
}

nonisolated final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let path: String

    init(url: URL, flags: Int32 = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX) throws {
        self.path = url.path
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            throw OfflineResourceImportError.sqliteFailure(lastErrorMessage())
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(handle, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage()
            sqlite3_free(errorPointer)
            throw OfflineResourceImportError.sqliteFailure(message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw OfflineResourceImportError.sqliteFailure(lastErrorMessage())
        }
        return statement
    }

    func error(_ prefix: String) -> OfflineResourceImportError {
        .sqliteFailure("\(prefix)：\(lastErrorMessage())")
    }

    private func lastErrorMessage() -> String {
        if let cString = sqlite3_errmsg(handle) {
            return String(cString: cString)
        }
        return "未知 SQLite 错误（\(path)）"
    }
}

private struct LineSequence: Sequence, IteratorProtocol {
    private let fileHandle: FileHandle
    private let delimiter = Data([0x0A])
    private var buffer = Data()
    private var isAtEOF = false

    init(url: URL) throws {
        self.fileHandle = try FileHandle(forReadingFrom: url)
    }

    mutating func next() -> String? {
        while !isAtEOF {
            if let range = buffer.range(of: delimiter) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                return String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            }

            let chunk = try? fileHandle.read(upToCount: 64 * 1024)

            if let chunk, !chunk.isEmpty {
                buffer.append(chunk)
            } else {
                isAtEOF = true
                if buffer.isEmpty {
                    try? fileHandle.close()
                    return nil
                }

                defer {
                    buffer.removeAll(keepingCapacity: false)
                    try? fileHandle.close()
                }
                return String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            }
        }

        try? fileHandle.close()
        return nil
    }
}
