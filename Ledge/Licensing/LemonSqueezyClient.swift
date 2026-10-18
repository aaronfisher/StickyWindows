import Foundation

/// Lemon Squeezy License API (https://docs.lemonsqueezy.com/api/license-api). Public endpoints; no API key.
struct LemonSqueezyClient: Sendable {
    struct LicenseKey: Decodable, Sendable {
        let id: Int
        let status: String
        let key: String
        let activationLimit: Int?
        let activationUsage: Int
        let expiresAt: String?
    }

    struct Instance: Decodable, Sendable {
        let id: String
        let name: String
    }

    struct Meta: Decodable, Sendable {
        let storeId: Int
        let productId: Int
        let productName: String?
        let customerName: String?
        let customerEmail: String?
    }

    struct Response: Decodable, Sendable {
        let activated: Bool?
        let valid: Bool?
        let deactivated: Bool?
        let error: String?
        let licenseKey: LicenseKey?
        let instance: Instance?
        let meta: Meta?
    }

    enum Failure: Error, LocalizedError {
        case server(String)
        case network(Error)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .server(let message): message
            case .network(let error): "Couldn't reach Lemon Squeezy: \(error.localizedDescription)"
            case .badResponse: "Unexpected reply from Lemon Squeezy."
            }
        }

        /// True when the server answered; the key itself is the problem, not the connection.
        var isDefinitive: Bool {
            if case .server = self { return true }
            return false
        }
    }

    private let base = URL(string: "https://api.lemonsqueezy.com/v1/licenses/")!
    var session: URLSession = .shared

    func activate(key: String, instanceName: String) async throws -> Response {
        try await post("activate", ["license_key": key, "instance_name": instanceName])
    }

    func validate(key: String, instanceID: String?) async throws -> Response {
        var fields = ["license_key": key]
        if let instanceID { fields["instance_id"] = instanceID }
        return try await post("validate", fields)
    }

    func deactivate(key: String, instanceID: String) async throws -> Response {
        try await post("deactivate", ["license_key": key, "instance_id": instanceID])
    }

    private func post(_ path: String, _ fields: [String: String]) async throws -> Response {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = Data(fields.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").utf8)

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw Failure.network(error)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data) else {
            throw Failure.badResponse
        }
        // Errors come back as 4xx with an "error" message; treat any message as the answer.
        if let message = response.error, !message.isEmpty {
            throw Failure.server(Self.humanize(message))
        }
        guard (urlResponse as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            throw Failure.badResponse
        }
        return response
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func humanize(_ message: String) -> String {
        switch message.lowercased() {
        case let m where m.contains("not found"): "That license key wasn't found. Check for typos."
        case let m where m.contains("activation limit"): "This key has reached its activation limit."
        case let m where m.contains("disabled"): "This license key has been disabled."
        case let m where m.contains("expired"): "This license key has expired."
        default: message
        }
    }
}
