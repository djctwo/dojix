import Foundation
import os

/// Handles communication with the Claude API for trade analysis
actor ClaudeService {
    private static let logger = Logger(subsystem: "com.dojix", category: "ClaudeService")

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session: URLSession

    /// Model used for analysis. Requests are billed to the API key the user enters.
    enum Model: String, Sendable {
        case standard = "claude-opus-5-5"
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        // Generous timeout: the model thinks before answering, which can take a while.
        self.session = SecureSession.make(timeout: 300)
    }

    // MARK: - API Communication

    struct Message: Codable, Sendable {
        let role: String
        let content: String
    }

    struct OutputConfig: Codable, Sendable {
        let effort: String
    }

    struct APIRequest: Codable, Sendable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
        let output_config: OutputConfig
        /// Server-side fallback: if a safety classifier declines the request, the API
        /// retries on Anthropic's recommended fallback model instead of refusing.
        let fallbacks: String
    }

    struct APIResponse: Codable, Sendable {
        let content: [ContentBlock]
        let stop_reason: String?
        let usage: Usage?

        struct ContentBlock: Codable, Sendable {
            let type: String
            let text: String?
        }

        struct Usage: Codable, Sendable {
            let input_tokens: Int
            let output_tokens: Int
        }
    }

    /// Send a message to Claude and get the text of its answer
    func send(
        system: String? = nil,
        messages: [Message],
        model: Model = .standard,
        maxTokens: Int = 16000
    ) async throws -> String {
        let request = APIRequest(
            model: model.rawValue,
            max_tokens: maxTokens,
            system: system,
            messages: messages,
            output_config: OutputConfig(effort: "medium"),
            fallbacks: "default"
        )

        guard let apiURL = URL(string: baseURL) else {
            throw ClaudeError.invalidResponse
        }
        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            Self.logger.error("API error \(httpResponse.statusCode)")
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: Self.errorMessage(from: data))
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("application/json") else {
            throw ClaudeError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        if apiResponse.stop_reason == "refusal" {
            throw ClaudeError.refused
        }

        // The answer is the concatenation of the text blocks (thinking blocks are skipped).
        let text = apiResponse.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ClaudeError.emptyResponse
        }

        if let usage = apiResponse.usage {
            Self.logger.info("Tokens: \(usage.input_tokens) in, \(usage.output_tokens) out")
        }

        return text
    }

    /// Pull the human-readable message out of an API error body (never echo the raw body).
    private static func errorMessage(from data: Data) -> String {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
        return String((message ?? "Unexpected response").prefix(300))
    }

    // MARK: - Errors

    enum ClaudeError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case emptyResponse
        case refused
        case noAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Invalid response from API"
            case .apiError(let code, let msg): "API error (\(code)): \(msg)"
            case .emptyResponse: "Empty response from API"
            case .refused: "The AI declined to answer this request."
            case .noAPIKey: "No API key configured. Add your Anthropic API key in Settings."
            }
        }
    }
}
