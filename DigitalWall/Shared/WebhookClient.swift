import Foundation
import Security

enum WebhookError: LocalizedError {
    case invalidURL, invalidToken, keychain(OSStatus), httpStatus(Int), invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter an HTTPS webhook URL without a username, password, or fragment."
        case .invalidToken: "The token must not contain spaces or line breaks."
        case .keychain: "Couldn’t access the webhook token in Keychain."
        case .httpStatus(let status): "Webhook returned HTTP \(status). Check your automation and token."
        case .invalidResponse: "The webhook didn’t return an HTTP response."
        }
    }
}

enum WebhookRequest {
    static func endpoint(_ text: String) throws -> URL {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil else { throw WebhookError.invalidURL }
        return url
    }

    static func validateToken(_ token: String) throws {
        guard token.unicodeScalars.allSatisfy({
            $0.value >= 33 && $0.value <= 126
        }) else { throw WebhookError.invalidToken }
    }

    static func make(payload: CheckInPayload, url: String, token: String) throws -> URLRequest {
        try validateToken(token)
        var request = URLRequest(url: try endpoint(url))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(payload.submissionID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)
        return request
    }
}

final class WebhookClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
        super.init()
    }

    func send(_ payload: CheckInPayload, url: String, token: String) async throws {
        let request = try WebhookRequest.make(payload: payload, url: url, token: token)
        let (_, response) = try await session.data(for: request, delegate: self)
        guard let response = response as? HTTPURLResponse else { throw WebhookError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw WebhookError.httpStatus(response.statusCode)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Never forward a private payload or bearer token to a redirected destination.
        completionHandler(nil)
    }

    static func message(for error: Error) -> String {
        if let error = error as? WebhookError { return error.localizedDescription }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return "Couldn’t reach the webhook. Saved locally; will retry automatically."
            default: return "The connection failed. Check the webhook URL and its HTTPS certificate."
            }
        }
        // Server bodies and error descriptions may contain private URLs or tokens.
        return "Couldn’t send the check-in. Saved locally; will retry automatically."
    }
}

enum WebhookSecret {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "DigitalWall") + ".webhook",
         kSecAttrAccount as String: "hour-check-in"]
    }

    static func read() throws -> String {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw WebhookError.keychain(status) }
        return token
    }

    static func write(_ token: String) throws {
        try WebhookRequest.validateToken(token)
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw WebhookError.keychain(status)
            }
            return
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw WebhookError.keychain(added) }
        } else if status != errSecSuccess {
            throw WebhookError.keychain(status)
        }
    }
}
