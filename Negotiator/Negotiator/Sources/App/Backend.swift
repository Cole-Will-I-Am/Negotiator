// negotiator-api client: Bearer auth, a generic JSON helper, and the streaming turn endpoint
// (NDJSON read via URLSession.AsyncBytes.lines — the DB8 pattern). Mirrors RUNG's Backend.swift.
import Foundation

enum BackendError: Error, LocalizedError {
    case network
    case server(Int, String)
    case decode
    var errorDescription: String? {
        switch self {
        case .network: return "Network error."
        case .server(let code, let msg): return "Server error \(code): \(msg)"
        case .decode: return "Could not read the server's response."
        }
    }
}

private struct ErrorBody: Decodable { let error: String }

final class Backend {
    static let baseURLString = "https://negotiator-api.manticthink.com"
    private let session = URLSession.shared

    private func enc<E: Encodable>(_ v: E) -> Data { (try? JSONEncoder().encode(v)) ?? Data("{}".utf8) }

    private func send<R: Decodable>(_ path: String, method: String = "GET",
                                    token: String? = nil, bodyData: Data? = nil) async throws -> R {
        guard let url = URL(string: Backend.baseURLString + path) else { throw BackendError.network }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BackendError.network }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "http \(http.statusCode)"
            throw BackendError.server(http.statusCode, msg)
        }
        do { return try JSONDecoder().decode(R.self, from: data) }
        catch { throw BackendError.decode }
    }

    // POST /v1/account — anonymous device registration / resume.
    func registerAnon(deviceId: String, deviceSecret: String?) async throws -> AccountResponse {
        struct B: Encodable { let deviceId: String; let deviceSecret: String? }
        return try await send("/v1/account", method: "POST", bodyData: enc(B(deviceId: deviceId, deviceSecret: deviceSecret)))
    }

    // POST /v1/session/start
    func startSession(token: String, levelId: String = "bartholomew") async throws -> SessionStartResponse {
        struct B: Encodable { let levelId: String }
        return try await send("/v1/session/start", method: "POST", token: token, bodyData: enc(B(levelId: levelId)))
    }

    // POST /v1/session/turn — returns the raw NDJSON byte stream for the caller to consume.
    func turnStream(token: String, sessionId: String, message: String) async throws -> URLSession.AsyncBytes {
        struct B: Encodable { let sessionId: String; let message: String }
        guard let url = URL(string: Backend.baseURLString + "/v1/session/turn") else { throw BackendError.network }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = enc(B(sessionId: sessionId, message: message))
        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BackendError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server(http.statusCode, "turn failed")
        }
        return bytes
    }
}
