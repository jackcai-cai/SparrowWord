import Foundation

/// Shared transport for the OpenAI Responses API.
///
/// Each generator builds its own request body and decodes its own schema from the
/// returned structured text; this client owns the parts that used to be duplicated
/// across all three generators: the endpoint, auth headers, HTTP status handling,
/// error-message decoding, and the response-envelope parsing.
///
/// Keeping the AI backend behind this single seam means swapping OpenAI for another
/// backend later (e.g. an on-device model) only touches this file.
struct OpenAIResponsesClient {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    let apiKey: String
    let session: URLSession

    nonisolated init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// POSTs a Responses request body and returns the model's structured output text.
    nonisolated func requestStructuredOutput(body: Data) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIContentGeneratorError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = Self.decodeAPIErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIContentGeneratorError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let payload = try JSONDecoder().decode(OpenAIResponsesPayload.self, from: data)
        return try payload.structuredOutputText()
    }

    nonisolated private static func decodeAPIErrorMessage(from data: Data) -> String? {
        guard
            let payload = try? JSONDecoder().decode(OpenAIErrorPayload.self, from: data),
            let message = payload.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        else {
            return nil
        }

        return message
    }
}

private struct OpenAIResponsesPayload: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    func structuredOutputText() throws -> String {
        if let outputText, !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.content)
            .flatMap { $0 }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let text, !text.isEmpty {
            return text
        }

        let refusal = output?
            .compactMap(\.content)
            .flatMap { $0 }
            .compactMap(\.refusal)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        if let refusal {
            throw OpenAIContentGeneratorError.modelRefused(refusal)
        }

        throw OpenAIContentGeneratorError.emptyOutput
    }

    struct OutputItem: Decodable {
        let content: [OutputContent]?
    }

    struct OutputContent: Decodable {
        let text: String?
        let refusal: String?
    }
}

private struct OpenAIErrorPayload: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String?
    }
}
