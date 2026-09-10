import Dispatch
import Foundation

extension Notification.Name {
    /// Postée sur le MainActor quand une requête reçoit un 401 avec un fingerprint connu.
    static let apiUnauthorized = Notification.Name("com.orvian2.api.unauthorized")
}

/// Client HTTP bas niveau (actor). Aucun appel réseau ni décodage sur le MainActor.
actor APIClient {
    static let shared = APIClient()
    static let baseURL = URL(string: "https://api.infomaniak.com")!

    private let session: URLSession
    private let decoder: JSONDecoder
    private var inFlightGETs: [String: Task<Data, Error>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024,
                                          diskCapacity: 150 * 1024 * 1024,
                                          diskPath: "api-url-cache")
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        self.decoder = decoder
    }

    // MARK: Requêtes

    @discardableResult
    func send<T: Decodable>(_ endpoint: Endpoint,
                            method: String = "GET",
                            body: Data? = nil,
                            contentType: String? = nil,
                            cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
                            requiresAuth: Bool = true) async throws -> T {
        let data = try await data(endpoint, method: method, body: body,
                                  contentType: contentType, cachePolicy: cachePolicy,
                                  requiresAuth: requiresAuth)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error, raw: data)
        }
    }

    /// Renvoie les octets bruts (pour les miniatures notamment).
    func dataRaw(_ endpoint: Endpoint,
                 method: String = "GET",
                 body: Data? = nil,
                 contentType: String? = nil,
                 cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
                 requiresAuth: Bool = true) async throws -> Data {
        try await data(endpoint, method: method, body: body, contentType: contentType,
                       cachePolicy: cachePolicy, requiresAuth: requiresAuth)
    }

    private func data(_ endpoint: Endpoint,
                      method: String,
                      body: Data?,
                      contentType: String?,
                      cachePolicy: URLRequest.CachePolicy,
                      requiresAuth: Bool) async throws -> Data {
        let request = try buildRequest(endpoint, method: method, body: body,
                                       contentType: contentType, cachePolicy: cachePolicy,
                                       requiresAuth: requiresAuth)
        let fingerprint = requiresAuth ? (TokenStore.credentialFingerprint() ?? "anon") : "anon"
        let fingerprintForCallback = TokenStore.credentialFingerprint()

        // Coalescing des GET identiques pour éviter les requêtes dupliquées.
        if method == "GET" {
            let key = "\(fingerprint)|\(cachePolicy.rawValue)|\(request.url?.absoluteString ?? "")"
            if let existing = inFlightGETs[key] { return try await existing.value }
            let task = Task<Data, Error> { [session] in
                let start = DispatchTime.now()
                let (data, response) = try await session.data(for: request)
                try Self.check(response: response, data: data, fingerprint: fingerprintForCallback)
                await Self.recordPerf(request: request, response: response, start: start)
                return data
            }
            inFlightGETs[key] = task
            defer { inFlightGETs[key] = nil }
            return try await task.value
        }

        let start = DispatchTime.now()
        let (data, response) = try await session.data(for: request)
        try Self.check(response: response, data: data, fingerprint: fingerprintForCallback)
        await Self.recordPerf(request: request, response: response, start: start)
        return data
    }

    /// Enregistre les métriques de performance réseau sur le MainActor.
    private static func recordPerf(request: URLRequest, response: URLResponse, start: DispatchTime) async {
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        guard let http = response as? HTTPURLResponse else { return }
        let fromCache = http.statusCode == 304 || (request.url.flatMap { _ in
            URLCache.shared.cachedResponse(for: request)
        } != nil && http.value(forHTTPHeaderField: "Age") != nil)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let bytes = http.expectedContentLength > 0 ? Int(http.expectedContentLength) : 0
        let status = http.statusCode
        await MainActor.run {
            Perf.shared.record(method: method, path: path, status: status,
                               durationMs: elapsedMs, bytes: bytes, fromCache: fromCache)
        }
    }

    private func buildRequest(_ endpoint: Endpoint,
                              method: String,
                              body: Data?,
                              contentType: String?,
                              cachePolicy: URLRequest.CachePolicy,
                              requiresAuth: Bool) throws -> URLRequest {
        guard var components = URLComponents(url: endpoint.base ?? Self.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = endpoint.path
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = cachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body { request.httpBody = body }

        // Auth requise sauf pour /1/ (endpoint de validation : token optionnel).
        if endpoint.path.hasPrefix("/1/") {
            if let token = TokenStore.current(), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        } else if requiresAuth {
            guard let token = TokenStore.current(), !token.isEmpty else { throw APIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: Vérification

    static func check(response: URLResponse, data: Data, fingerprint: String?) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401, let fingerprint {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .apiUnauthorized, object: fingerprint)
                }
            }
            let parsed = decodeError(data)
            throw APIError.http(status: http.statusCode, code: parsed?.code, description: parsed?.description)
        }
    }

    static func decodeError(_ data: Data) -> (code: String?, description: String?)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        let code = error["code"].map { "\($0)" }
        let description = error["description"] as? String
        return (code, description)
    }

    // MARK: Uploads

    /// Upload par streaming depuis le disque (fichiers volumineux).
    func uploadFile(_ fileURL: URL,
                    endpoint: Endpoint,
                    method: String = "POST",
                    contentType: String = "application/octet-stream",
                    progress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
        let request = try buildUploadRequest(endpoint, method: method, contentType: contentType)
        return try await performUpload(request: request, fromFile: fileURL, progress: progress)
    }

    func uploadData(_ body: Data,
                    endpoint: Endpoint,
                    method: String = "POST",
                    contentType: String = "application/octet-stream",
                    progress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
        let request = try buildUploadRequest(endpoint, method: method, contentType: contentType)
        return try await performUpload(request: request, from: body, progress: progress)
    }

    private func buildUploadRequest(_ endpoint: Endpoint,
                                    method: String,
                                    contentType: String) throws -> URLRequest {
        guard var components = URLComponents(url: endpoint.base ?? Self.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = endpoint.path
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 300
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if !endpoint.path.hasPrefix("/1/") {
            guard let token = TokenStore.current(), !token.isEmpty else { throw APIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func performUpload(request: URLRequest,
                               from body: Data,
                               progress: (@Sendable (Double) -> Void)?) async throws -> Data {
        let delegate = UploadProgressDelegate(onProgress: progress)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        let uploadSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await uploadSession.upload(for: request, from: body)
            try Self.check(response: response, data: data, fingerprint: nil)
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private func performUpload(request: URLRequest,
                               fromFile fileURL: URL,
                               progress: (@Sendable (Double) -> Void)?) async throws -> Data {
        let delegate = UploadProgressDelegate(onProgress: progress)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        let uploadSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await uploadSession.upload(for: request, fromFile: fileURL)
            try Self.check(response: response, data: data, fingerprint: nil)
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }
}

/// Suivi de progression d'upload.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?
    private var lastReported = 0.0

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0, let onProgress else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        if fraction - lastReported >= 0.01 || fraction >= 1 {
            lastReported = fraction
            onProgress(fraction)
        }
    }
}

private extension URL {
    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 ?? 0
    }
}
