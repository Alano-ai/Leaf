// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum DeepSeekClient {
    enum Issue: LocalizedError, Equatable {
        case authentication, balance, rateLimited, service, invalidResponse, network

        var errorDescription: String? {
            switch self {
            case .authentication: String(localized: "DeepSeek rejected the API key. Check the key in Leaf Settings.")
            case .balance: String(localized: "The DeepSeek API account has insufficient balance.")
            case .rateLimited: String(localized: "DeepSeek is rate limiting this account. Try again later.")
            case .service: String(localized: "DeepSeek could not complete the check.")
            case .invalidResponse: String(localized: "DeepSeek did not return readable suggestions.")
            case .network: String(localized: "Leaf could not connect to DeepSeek.")
            }
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model = "deepseek-flash"
        let thinking = ["type": "disabled"]
        let max_tokens = 650
        let messages: [Message]
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func analyze(_ snapshot: CompatibilitySnapshot, key: String, inChinese: Bool) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let request = try makeRequest(snapshot, key: key, inChinese: inChinese)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Issue.network
        }
        guard let http = response as? HTTPURLResponse else { throw Issue.invalidResponse }
        return try parse(data, status: http.statusCode)
    }

    static func makeRequest(_ snapshot: CompatibilitySnapshot, key: String, inChinese: Bool) throws -> URLRequest {
        let key = try DeepSeekKeychain.validatedKey(key)
        let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
        let language = inChinese ? "Simplified Chinese" : "English"
        let prompt = """
        Explain the supplied local ebook structure checks in \(language). Give up to four short, practical suggestions         for importing the file into a Kindle or another reader. Mention likely causes only when supported by the numbers.         When an original report is present, compare missing images, navigation and selectable text cautiously since         conversion and reflow may change counts. These checks cannot establish device or Send to Kindle compatibility.         Do not imply access to the book or suggest bypassing DRM. Return plain text without links.
        """
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let facts = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        let body = RequestBody(messages: [Message(role: "system", content: prompt),
                                          Message(role: "user", content: facts)])
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)
        return request
    }

    static func parse(_ data: Data, status: Int) throws -> String {
        switch status {
        case 200: break
        case 401, 403: throw Issue.authentication
        case 402: throw Issue.balance
        case 429: throw Issue.rateLimited
        default: throw Issue.service
        }
        guard data.count <= 128_000, let response = try? JSONDecoder().decode(Response.self, from: data),
              let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw Issue.invalidResponse }
        return text
    }
}
