import Foundation
import Security

final class KeychainService {
    private let currentService = "com.JackCai.SparrowWord"
    private let legacyServices = [
        "com.JackCai.VoiceNotesMac",
    ]
    private let account = "openai_api_key"

    func loadOpenAIAPIKey() -> String {
        for service in [currentService] + legacyServices {
            let apiKey = loadOpenAIAPIKey(for: service)
            if !apiKey.isEmpty {
                return apiKey
            }
        }

        return ""
    }

    func saveOpenAIAPIKey(_ apiKey: String) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAPIKey.isEmpty else {
            try deleteOpenAIAPIKey()
            return
        }

        let data = Data(trimmedAPIKey.utf8)
        let query = baseQuery(service: currentService)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                throw KeychainServiceError.operationFailed(status: addStatus)
            }
        default:
            throw KeychainServiceError.operationFailed(status: updateStatus)
        }

        for service in legacyServices {
            SecItemDelete(baseQuery(service: service) as CFDictionary)
        }
    }

    func deleteOpenAIAPIKey() throws {
        for service in [currentService] + legacyServices {
            let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainServiceError.operationFailed(status: status)
            }
        }
    }

    private func loadOpenAIAPIKey(for service: String) -> String {
        var query = baseQuery(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            return ""
        }

        guard
            let data = item as? Data,
            let apiKey = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum KeychainServiceError: LocalizedError {
    case operationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown keychain error"
            return "Keychain 操作失败（\(status)）：\(message)"
        }
    }
}
