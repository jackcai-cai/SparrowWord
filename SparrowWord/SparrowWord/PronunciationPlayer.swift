import AVFoundation
import Foundation

@MainActor
final class PronunciationPlayer {
    static let shared = PronunciationPlayer()

    private let synthesizer = AVSpeechSynthesizer()
    private let englishVoiceCodes = ["en-US", "en-GB", "en-AU", "en-IE"]
    private let chineseVoiceCodes = ["zh-CN", "zh-HK", "zh-TW"]

    private init() {}

    func speak(
        _ text: String,
        displayLanguage: AppDisplayLanguage,
        voicePreference: PronunciationVoicePreference
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        let preferredCodes = preferredLanguageCodes(
            for: trimmed,
            displayLanguage: displayLanguage,
            voicePreference: voicePreference
        )
        utterance.voice = preferredVoice(for: preferredCodes)
            ?? AVSpeechSynthesisVoice(language: preferredCodes.first ?? "en-US")
        utterance.rate = preferredCodes.first?.hasPrefix("zh") == true ? 0.42 : 0.45
        synthesizer.speak(utterance)
    }

    private func preferredLanguageCodes(
        for text: String,
        displayLanguage: AppDisplayLanguage,
        voicePreference: PronunciationVoicePreference
    ) -> [String] {
        switch voicePreference {
        case .chinese:
            return chineseVoiceCodes
        case .english:
            return englishVoiceCodes
        case .automatic:
            if containsChineseCharacters(in: text) {
                return chineseVoiceCodes
            }

            switch displayLanguage {
            case .chinese, .english:
                return englishVoiceCodes
            }
        }
    }

    private func preferredVoice(for languageCodes: [String]) -> AVSpeechSynthesisVoice? {
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()

        for languageCode in languageCodes {
            if let exactMatch = availableVoices.first(where: { $0.language == languageCode }) {
                return exactMatch
            }

            let loweredCode = languageCode.lowercased()
            if let prefixMatch = availableVoices.first(where: { $0.language.lowercased().hasPrefix(loweredCode) }) {
                return prefixMatch
            }
        }

        return nil
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
}
