import Foundation

enum SentenceTranslationServiceError: LocalizedError {
    case missingResources
    case bootstrapFailed(String)
    case translationFailed(String)
    case missingPython
    case unsupportedPythonVersion(String)

    var errorDescription: String? {
        switch self {
        case .missingResources:
            return "本地句子翻译资源还没有导入。"
        case .bootstrapFailed(let message):
            return "本地句子翻译引擎准备失败：\(message)"
        case .translationFailed(let message):
            return "本地句子翻译失败：\(message)"
        case .missingPython:
            return "没有找到可用的 Python 3.12 / 3.11 运行时。请先安装 Homebrew Python 3.12。"
        case .unsupportedPythonVersion(let version):
            return "当前只找到 Python \(version)。离线句子翻译请安装 Homebrew Python 3.12（推荐）或 3.11；Python 3.13 在沙盒里容易因为依赖编译而失败。"
        }
    }
}

nonisolated final class LocalSentenceTranslationService {
    private let storage: StorageService
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(storage: StorageService = StorageService()) {
        self.storage = storage
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func translate(
        text: String,
        direction: SentenceTranslationDirection,
        manifest: OfflineResourceManifest
    ) throws -> [String] {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            return []
        }

        guard manifest.isImported, !manifest.argosPackagesDirectoryPath.isEmpty else {
            throw SentenceTranslationServiceError.missingResources
        }

        let cacheKey = "\(direction.rawValue)::\(cleanedText)"
        var cache = loadCache()
        if let cached = cache[cacheKey], !cached.isEmpty {
            return cached
        }

        try bootstrapIfNeeded(manifest: manifest)
        let helperPython = pythonExecutable(in: manifest)

        let response: PythonHelperResponse = try runHelper(
            pythonExecutable: helperPython,
            manifest: manifest,
            request: PythonHelperRequest(
                command: "translate",
                modelsDirectory: manifest.argosPackagesDirectoryPath,
                direction: direction.rawValue,
                text: cleanedText
            )
        )

        guard response.ok else {
            throw SentenceTranslationServiceError.translationFailed(response.error ?? "未知错误")
        }

        let translations = response.translations?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        guard !translations.isEmpty else {
            throw SentenceTranslationServiceError.translationFailed("本地翻译结果为空")
        }

        cache[cacheKey] = translations
        saveCache(cache)
        return translations
    }

    func bootstrapIfNeeded(manifest: OfflineResourceManifest) throws {
        guard manifest.isImported, !manifest.argosPackagesDirectoryPath.isEmpty else {
            throw SentenceTranslationServiceError.missingResources
        }

        let helperDirectory = URL(fileURLWithPath: manifest.pythonHelperDirectoryPath, isDirectory: true)
        try fileManager.createDirectory(at: helperDirectory, withIntermediateDirectories: true)

        let helperScript = helperDirectory.appendingPathComponent("argos_helper.py")
        try helperScriptString().write(to: helperScript, atomically: true, encoding: .utf8)

        let pythonRuntime = try resolveSystemPython()
        let pythonExecutable = pythonRuntime.executableURL
        let venvDirectory = helperDirectory.appendingPathComponent("venv", isDirectory: true)
        let bootstrapMarker = helperDirectory.appendingPathComponent("bootstrap-1.9.6-py\(pythonRuntime.major).\(pythonRuntime.minor).ok")

        try resetVirtualEnvironmentIfNeeded(
            venvDirectory: venvDirectory,
            selectedRuntime: pythonRuntime,
            helperDirectory: helperDirectory
        )

        if !fileManager.fileExists(atPath: venvDirectory.path) {
            try runProcess(
                executableURL: pythonExecutable,
                arguments: ["-m", "venv", venvDirectory.path]
            )
        }

        let venvPython = venvDirectory.appendingPathComponent("bin/python3")
        let venvPip = venvDirectory.appendingPathComponent("bin/pip3")

        if !fileManager.fileExists(atPath: bootstrapMarker.path) {
            do {
                try runProcess(
                    executableURL: venvPip,
                    arguments: ["install", "--upgrade", "pip", "setuptools", "wheel"]
                )

                try runProcess(
                    executableURL: venvPip,
                    arguments: ["install", "--prefer-binary", "argostranslate==1.9.6"]
                )

                let response: PythonHelperResponse = try runHelper(
                    pythonExecutable: venvPython,
                    manifest: manifest,
                    request: PythonHelperRequest(
                        command: "bootstrap",
                        modelsDirectory: manifest.argosPackagesDirectoryPath,
                        direction: nil,
                        text: nil
                    )
                )

                guard response.ok else {
                    throw SentenceTranslationServiceError.bootstrapFailed(response.error ?? "未知错误")
                }

                try "ok".write(to: bootstrapMarker, atomically: true, encoding: .utf8)
            } catch {
                cleanupVirtualEnvironment(at: venvDirectory, helperDirectory: helperDirectory)
                throw error
            }
        }
    }

    private func pythonExecutable(in manifest: OfflineResourceManifest) -> URL {
        URL(fileURLWithPath: manifest.pythonHelperDirectoryPath, isDirectory: true)
            .appendingPathComponent("venv/bin/python3")
    }

    private func resolveSystemPython() throws -> PythonRuntime {
        let candidates = pythonCandidates()
        var unsupportedRuntime: PythonRuntime?

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            guard let runtime = inspectPythonExecutable(candidate) else {
                continue
            }

            guard runtime.major == 3 else {
                continue
            }

            if runtime.isSupportedForArgosBootstrap {
                return runtime
            }

            if unsupportedRuntime == nil {
                unsupportedRuntime = runtime
            }
        }

        if let unsupportedRuntime {
            throw SentenceTranslationServiceError.unsupportedPythonVersion(unsupportedRuntime.versionString)
        }

        throw SentenceTranslationServiceError.missingPython
    }

    private func inspectPythonExecutable(_ executableURL: URL) -> PythonRuntime? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = [
            "-c",
            "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')"
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }

            let output = stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()
            let versionText = String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return PythonRuntime(executableURL: executableURL, versionText: versionText)
        } catch {
            return nil
        }
    }

    private func pythonCandidates() -> [URL] {
        let preferredPaths = [
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/opt/python@3.12/bin/python3.12",
            "/usr/local/bin/python3.12",
            "/usr/local/opt/python@3.12/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/opt/python@3.11/bin/python3.11",
            "/usr/local/bin/python3.11",
            "/usr/local/opt/python@3.11/bin/python3.11",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]

        var seen = Set<String>()
        return preferredPaths.compactMap { path in
            guard seen.insert(path).inserted else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
    }

    private func resetVirtualEnvironmentIfNeeded(
        venvDirectory: URL,
        selectedRuntime: PythonRuntime,
        helperDirectory: URL
    ) throws {
        let venvPython = venvDirectory.appendingPathComponent("bin/python3")
        guard fileManager.fileExists(atPath: venvPython.path) else {
            return
        }

        guard let existingRuntime = inspectPythonExecutable(venvPython),
              existingRuntime.isSupportedForArgosBootstrap,
              existingRuntime.major == selectedRuntime.major,
              existingRuntime.minor == selectedRuntime.minor else {
            cleanupVirtualEnvironment(at: venvDirectory, helperDirectory: helperDirectory)
            return
        }
    }

    private func cleanupVirtualEnvironment(at venvDirectory: URL, helperDirectory: URL) {
        if fileManager.fileExists(atPath: venvDirectory.path) {
            try? fileManager.removeItem(at: venvDirectory)
        }

        let markerPrefix = "bootstrap-1.9.6"
        if let helperContents = try? fileManager.contentsOfDirectory(at: helperDirectory, includingPropertiesForKeys: nil) {
            for item in helperContents where item.lastPathComponent.hasPrefix(markerPrefix) {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private func runHelper<T: Decodable>(
        pythonExecutable: URL,
        manifest: OfflineResourceManifest,
        request: PythonHelperRequest
    ) throws -> T {
        let helperScript = URL(fileURLWithPath: manifest.pythonHelperDirectoryPath, isDirectory: true)
            .appendingPathComponent("argos_helper.py")

        let requestData = try encoder.encode(request)
        let output = try runProcess(
            executableURL: pythonExecutable,
            arguments: [helperScript.path],
            stdin: requestData
        )

        return try decoder.decode(T.self, from: output)
    }

    @discardableResult
    private func runProcess(executableURL: URL, arguments: [String], stdin: Data? = nil) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        if stdin != nil {
            process.standardInput = stdinPipe
        }

        try process.run()

        if let stdin {
            stdinPipe.fileHandleForWriting.write(stdin)
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let fallback = "子进程退出码 \(process.terminationStatus)"
            let errorText = sanitizedProcessErrorMessage(
                String(data: errorOutput, encoding: .utf8) ?? "",
                fallback: fallback
            )
            throw SentenceTranslationServiceError.bootstrapFailed(errorText)
        }

        return output
    }

    private func sanitizedProcessErrorMessage(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback
        }

        if trimmed.contains("cannot be used within an App Sandbox")
            || trimmed.contains("pip-build-env")
            || trimmed.contains("python3.13/site-packages") {
            return "依赖安装触发了本地编译。请改用 Homebrew Python 3.12（推荐）或 3.11。"
        }

        if trimmed.contains("No matching distribution found for argostranslate") {
            return "当前 Python 版本没有可用的 argostranslate 预编译包。请安装 Homebrew Python 3.12。"
        }

        if trimmed.contains("No matching distribution found for sacremoses==0.0.53") {
            return "依赖安装策略过严，拦住了纯 Python 的 sacremoses。更新后会改用更稳妥的安装方式。"
        }

        let interestingLines = trimmed
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("File ") && !$0.hasPrefix("Traceback") }

        if let pipErrorLine = interestingLines.last(where: { line in
            line.localizedCaseInsensitiveContains("error")
                || line.localizedCaseInsensitiveContains("failed")
                || line.localizedCaseInsensitiveContains("No matching distribution")
        }) {
            return pipErrorLine
        }

        if let lastMeaningfulLine = interestingLines.last {
            return lastMeaningfulLine
        }

        return fallback
    }

    private func loadCache() -> [String: [String]] {
        let url = storage.translationCacheURL()
        guard let data = try? Data(contentsOf: url),
              let cache = try? decoder.decode([String: [String]].self, from: data) else {
            return [:]
        }

        return cache
    }

    private func saveCache(_ cache: [String: [String]]) {
        guard let data = try? encoder.encode(cache) else {
            return
        }

        try? FileManager.default.createDirectory(at: storage.baseDirectory(), withIntermediateDirectories: true)
        try? data.write(to: storage.translationCacheURL(), options: .atomic)
    }

    private func helperScriptString() -> String {
        #"""
import json
import os
import sys
import zipfile

import argostranslate.package
import argostranslate.translate


def load_request():
    raw = sys.stdin.read()
    return json.loads(raw or "{}")


def list_installed_pairs():
    installed = set()
    for from_lang in argostranslate.translate.get_installed_languages():
        for translation in from_lang.translations_from:
            installed.add((from_lang.code, translation.to_lang.code))
    return installed


def bootstrap(models_dir):
    installed_pairs = list_installed_pairs()
    for name in sorted(os.listdir(models_dir)):
        if not name.endswith(".argosmodel"):
            continue
        package_path = os.path.join(models_dir, name)
        with zipfile.ZipFile(package_path) as zf:
            metadata_name = next(item for item in zf.namelist() if item.endswith("metadata.json"))
            metadata = json.loads(zf.read(metadata_name).decode("utf-8"))
        pair = (metadata["from_code"], metadata["to_code"])
        if pair in installed_pairs:
            continue
        argostranslate.package.install_from_path(package_path)
        installed_pairs = list_installed_pairs()

    return {"ok": True, "installed_pairs": sorted(["%s->%s" % pair for pair in installed_pairs])}


def translate(direction, text):
    if direction == "englishToChinese":
        from_code, to_code = "en", "zh"
    else:
        from_code, to_code = "zh", "en"

    installed_languages = {lang.code: lang for lang in argostranslate.translate.get_installed_languages()}
    from_lang = installed_languages.get(from_code)
    to_lang = installed_languages.get(to_code)
    if from_lang is None or to_lang is None:
        return {"ok": False, "error": "缺少 %s -> %s 的本地翻译模型" % (from_code, to_code)}

    translation = from_lang.get_translation(to_lang)
    if translation is None:
        return {"ok": False, "error": "没有找到可用的本地翻译方向 %s -> %s" % (from_code, to_code)}

    return {"ok": True, "translations": [translation.translate(text)]}


def main():
    request = load_request()
    command = request.get("command")

    try:
        if command == "bootstrap":
            response = bootstrap(request["modelsDirectory"])
        elif command == "translate":
            response = translate(request["direction"], request["text"])
        else:
            response = {"ok": False, "error": "未知命令"}
    except Exception as exc:
        response = {"ok": False, "error": str(exc)}

    sys.stdout.write(json.dumps(response, ensure_ascii=False))


if __name__ == "__main__":
    main()
"""#
    }
}

private struct PythonRuntime: Equatable, Sendable {
    let executableURL: URL
    let major: Int
    let minor: Int
    let patch: Int

    nonisolated init?(executableURL: URL, versionText: String) {
        let components = versionText
            .split(separator: ".")
            .compactMap { Int($0) }

        guard components.count >= 2 else {
            return nil
        }

        self.executableURL = executableURL
        self.major = components[0]
        self.minor = components[1]
        self.patch = components.count >= 3 ? components[2] : 0
    }

    nonisolated var versionString: String {
        "\(major).\(minor).\(patch)"
    }

    nonisolated var isSupportedForArgosBootstrap: Bool {
        major == 3 && (minor == 11 || minor == 12)
    }
}

private struct PythonHelperRequest: Encodable, Sendable {
    var command: String
    var modelsDirectory: String?
    var direction: String?
    var text: String?
}

private struct PythonHelperResponse: Decodable, Sendable {
    var ok: Bool
    var error: String?
    var translations: [String]?
}
