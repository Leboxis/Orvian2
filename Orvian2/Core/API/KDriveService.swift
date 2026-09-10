import Foundation

/// Source de listing de fichiers.
enum FileSource: Hashable {
    case directory(Int)
    case favorites(limit: Int)
    case recents(limit: Int)
    case category(Int)
    case trash
    case search(query: String, directoryId: Int?)

    var stableKey: String {
        switch self {
        case let .directory(id): return "dir-\(id)"
        case let .favorites(limit): return "favorites-\(limit)"
        case let .recents(limit): return "recents-\(limit)"
        case let .category(id): return "category-\(id)"
        case .trash: return "trash"
        case let .search(query, directoryId): return "search-\(directoryId.map(String.init) ?? "all")-\(query)"
        }
    }

    /// Une recherche n'est jamais mise en cache disque.
    var isPersistedList: Bool {
        switch self {
        case .favorites, .recents: return true
        default: return false
        }
    }
}

/// Repository kDrive au-dessus de l'`APIClient`.
struct KDriveService: Sendable {
    static let directUploadLimit = 95 * 1024 * 1024
    static let uploadChunkSize = 20 * 1024 * 1024
    static let uploadChunkMaximumAttempts = 3

    static let browsableOrderingFields: Set<String> = [
        "added_at", "last_modified_at", "mime_type", "name", "revised_at", "size", "type", "updated_at"
    ]

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: Comptes / drives

    func accounts() async throws -> [InfomaniakAccount] {
        let response: DataResponse<[InfomaniakAccount]> = try await client.send(APIEndpoint.accounts())
        return response.data ?? []
    }

    func drives(accountId: Int) async throws -> [Drive] {
        let response: DataResponse<[Drive]> = try await client.send(APIEndpoint.drives(accountId: accountId))
        return response.data ?? []
    }

    /// Parcourt les comptes et retourne le premier disposant de drives.
    func discoverDrives() async throws -> (accountId: Int, drives: [Drive]) {
        let accounts = try await accounts()
        for account in accounts {
            let drives = try await drives(accountId: account.id)
            if !drives.isEmpty { return (account.id, drives) }
        }
        throw APIError.http(status: 404, code: "no_drive", description: "Aucun drive trouvé pour ce compte.")
    }

    // MARK: Listing (page)

    func page(_ source: FileSource,
              driveId: Int,
              cursor: String? = nil,
              orderBy: [String]? = nil,
              order: String = "asc",
              forceNetwork: Bool = false) async throws -> CursorPage<DriveFile> {
        let policy: URLRequest.CachePolicy = forceNetwork ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        switch source {
        case let .directory(directoryId):
            var endpoint = APIEndpoint.directoryContent(driveId: driveId, directoryId: directoryId)
            if let cursor { endpoint.query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let safe = safeOrdering(orderBy) ?? ["type", "name"]
            endpoint = endpoint.ordering(safe, order: orderBy == nil ? "asc" : order)
            return try await client.send(endpoint, cachePolicy: policy)
        case let .favorites(limit):
            var endpoint = APIEndpoint.favorites(driveId: driveId)
            endpoint.query = Self.replacingLimit(endpoint.query, limit: limit)
            if let cursor { endpoint.query.append(URLQueryItem(name: "cursor", value: cursor)) }
            if let orderBy, let safe = safeOrdering(orderBy) {
                endpoint = endpoint.ordering(safe, order: order)
            }
            return try await client.send(endpoint, cachePolicy: policy)
        case let .recents(limit):
            return try await recentsPage(driveId: driveId, limit: limit, cursor: cursor,
                                         orderBy: orderBy, order: order, policy: policy)
        case let .category(categoryId):
            var endpoint = APIEndpoint.search(driveId: driveId)
            endpoint.query.append(URLQueryItem(name: "category", value: String(categoryId)))
            endpoint.query.append(URLQueryItem(name: "depth", value: "unlimited"))
            if let cursor { endpoint.query.append(URLQueryItem(name: "cursor", value: cursor)) }
            return try await client.send(endpoint, cachePolicy: policy)
        case .trash:
            var endpoint = APIEndpoint.trashContent(driveId: driveId)
            if let cursor { endpoint.query.append(URLQueryItem(name: "cursor", value: cursor)) }
            return try await client.send(endpoint, cachePolicy: policy)
        case let .search(query, directoryId):
            var endpoint = APIEndpoint.search(driveId: driveId)
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { endpoint.query.append(URLQueryItem(name: "query", value: trimmed)) }
            if let directoryId { endpoint.query.append(URLQueryItem(name: "directory_id", value: String(directoryId))) }
            endpoint.query.append(URLQueryItem(name: "depth", value: "unlimited"))
            if let cursor { endpoint.query.append(URLQueryItem(name: "cursor", value: cursor)) }
            return try await client.send(endpoint, cachePolicy: policy)
        }
    }

    private static func replacingLimit(_ query: [URLQueryItem], limit: Int) -> [URLQueryItem] {
        var result = query.filter { $0.name != "limit" }
        result.append(URLQueryItem(name: "limit", value: String(limit)))
        return result
    }

    /// Normalise les champs de tri ; renvoie nil si aucun supporté (endpoint inchangé).
    private func safeOrdering(_ orderBy: [String]?) -> [String]? {
        guard let orderBy, !orderBy.isEmpty else { return nil }
        let filtered = orderBy.filter { Self.browsableOrderingFields.contains($0) }
        return filtered.isEmpty ? nil : filtered
    }

    /// Cascade de repli pour « récents » : last_modified → recents → activities → search.
    private func recentsPage(driveId: Int, limit: Int, cursor: String?,
                             orderBy: [String]?, order: String,
                             policy: URLRequest.CachePolicy) async throws -> CursorPage<DriveFile> {
        // 1. last_modified
        do {
            var endpoint = Self.withLimit(APIEndpoint.lastModified(driveId: driveId), limit: limit, cursor: cursor)
            return try await client.send(endpoint, cachePolicy: policy)
        } catch let error as APIError { guard error.isFallbackCandidate else { throw error } }

        // 2. recents
        do {
            let endpoint = Self.withLimit(APIEndpoint.recents(driveId: driveId), limit: limit, cursor: cursor)
            return try await client.send(endpoint, cachePolicy: policy)
        } catch let error as APIError { guard error.isFallbackCandidate else { throw error } }

        // 3. activities (le fichier est encapsulé sous la clé `file`)
        do {
            let endpoint = Self.withLimit(APIEndpoint.activities(driveId: driveId), limit: limit, cursor: cursor)
            let page: CursorPage<ActivityWrapper> = try await client.send(endpoint, cachePolicy: policy)
            return CursorPage(result: page.result,
                              data: page.data.compactMap { $0.file },
                              cursor: page.cursor,
                              hasMore: page.hasMore)
        } catch let error as APIError { guard error.isFallbackCandidate else { throw error } }

        // 4. search (dernier recours)
        var endpoint = APIEndpoint.search(driveId: driveId)
        endpoint.query.append(URLQueryItem(name: "depth", value: "unlimited"))
        if let cursor { endpoint.query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await client.send(endpoint, cachePolicy: policy)
    }

    private static func withLimit(_ endpoint: Endpoint, limit: Int, cursor: String?) -> Endpoint {
        var result = endpoint
        result.query = Self.replacingLimit(result.query, limit: limit)
        if let cursor { result.query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return result
    }

    private struct ActivityWrapper: Codable {
        let file: DriveFile?
    }

    // MARK: Détails

    func fileInfo(driveId: Int, fileId: Int) async throws -> DriveFile {
        let response: DataResponse<DriveFile> = try await client.send(
            APIEndpoint.fileInfo(driveId: driveId, fileId: fileId))
        guard let file = response.data else { throw APIError.invalidResponse }
        return file
    }

    func directoryCount(driveId: Int, directoryId: Int) async throws -> DirectoryCount {
        let response: DataResponse<DirectoryCount> = try await client.send(
            APIEndpoint.directoryCount(driveId: driveId, directoryId: directoryId))
        guard let count = response.data else { throw APIError.invalidResponse }
        return count
    }

    // MARK: Catégories

    func categories(driveId: Int) async throws -> [Category] {
        let response: CursorPage<Category> = try await client.send(APIEndpoint.categories(driveId: driveId))
        return response.data
    }

    func createCategory(driveId: Int, name: String, color: String?) async throws -> Category {
        var body: [String: Any] = ["name": name]
        if let color { body["color"] = color }
        let data = try JSONSerialization.data(withJSONObject: body)
        let response: DataResponse<Category> = try await client.send(
            APIEndpoint.categories(driveId: driveId), method: "POST", body: data,
            contentType: "application/json", cachePolicy: .reloadIgnoringLocalCacheData)
        guard let category = response.data else { throw APIError.invalidResponse }
        return category
    }

    func updateCategory(driveId: Int, categoryId: Int, name: String, color: String?) async throws -> Category {
        var body: [String: Any] = ["name": name]
        if let color { body["color"] = color }
        let data = try JSONSerialization.data(withJSONObject: body)
        let response: DataResponse<Category> = try await client.send(
            APIEndpoint.category(driveId: driveId, categoryId: categoryId), method: "PUT", body: data,
            contentType: "application/json", cachePolicy: .reloadIgnoringLocalCacheData)
        guard let category = response.data else { throw APIError.invalidResponse }
        return category
    }

    func deleteCategory(driveId: Int, categoryId: Int) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.category(driveId: driveId, categoryId: categoryId), method: "DELETE",
            cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func addCategory(driveId: Int, fileId: Int, categoryId: Int) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.fileCategory(driveId: driveId, fileId: fileId, categoryId: categoryId),
            method: "POST", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func removeCategory(driveId: Int, fileId: Int, categoryId: Int) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.fileCategory(driveId: driveId, fileId: fileId, categoryId: categoryId),
            method: "DELETE", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    // MARK: Favoris / miniatures / URL

    func setFavorite(driveId: Int, fileId: Int, isFavorite: Bool) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.favorite(driveId: driveId, fileId: fileId),
            method: isFavorite ? "POST" : "DELETE", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func thumbnailData(driveId: Int, fileId: Int, isTrashed: Bool = false) async throws -> Data {
        let endpoint = isTrashed
            ? APIEndpoint.trashedThumbnail(driveId: driveId, fileId: fileId)
            : APIEndpoint.thumbnail(driveId: driveId, fileId: fileId)
        return try await client.dataRaw(endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func temporaryURL(driveId: Int, fileId: Int, duration: Int = 3600) async throws -> URL {
        let response: DataResponse<TemporaryURL> = try await client.send(
            APIEndpoint.temporaryURL(driveId: driveId, fileId: fileId, duration: duration))
        guard let value = response.data?.temporaryURL, let url = URL(string: value) else {
            throw APIError.invalidResponse
        }
        return url
    }

    // MARK: Mutations

    func createFolder(driveId: Int, directoryId: Int, name: String) async throws -> DriveFile {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let response: DataResponse<DriveFile> = try await client.send(
            APIEndpoint.createFolder(driveId: driveId, directoryId: directoryId),
            method: "POST", body: body, contentType: "application/json",
            cachePolicy: .reloadIgnoringLocalCacheData)
        guard let file = response.data else { throw APIError.invalidResponse }
        return file
    }

    func rename(driveId: Int, fileId: Int, name: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        _ = try await client.dataRaw(
            APIEndpoint.rename(driveId: driveId, fileId: fileId), method: "POST", body: body,
            contentType: "application/json", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func setFolderColor(driveId: Int, fileId: Int, color: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["color": color])
        _ = try await client.dataRaw(
            APIEndpoint.folderColor(driveId: driveId, fileId: fileId), method: "POST", body: body,
            contentType: "application/json", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func move(driveId: Int, fileId: Int, destinationId: Int) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.move(driveId: driveId, fileId: fileId, destinationId: destinationId),
            method: "POST", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func trash(driveId: Int, fileId: Int) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.trash(driveId: driveId, fileId: fileId), method: "DELETE",
            cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func permanentlyDelete(driveId: Int, fileId: Int) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.permanentDelete(driveId: driveId, fileId: fileId), method: "DELETE",
            cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func restore(driveId: Int, fileId: Int, destinationId: Int) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["destination_directory_id": destinationId])
        _ = try await client.dataRaw(
            APIEndpoint.restore(driveId: driveId, fileId: fileId), method: "POST", body: body,
            contentType: "application/json", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    // MARK: Upload

    /// Nouvelle version d'un contenu existant.
    func uploadContent(driveId: Int, fileId: Int, data: Data, totalSize: Int, lastModifiedAt: Int?) async throws {
        var endpoint = APIEndpoint.upload(driveId: driveId)
        endpoint.query.append(URLQueryItem(name: "file_id", value: String(fileId)))
        endpoint.query.append(URLQueryItem(name: "total_size", value: String(totalSize)))
        if let lastModifiedAt {
            endpoint.query.append(URLQueryItem(name: "last_modified_at", value: String(lastModifiedAt)))
        }
        let responseData = try await client.uploadData(data, endpoint: endpoint)
        try validateUpload(responseData)
    }

    /// Upload d'un fichier : direct < 95 Mo, sinon session chunkée.
    func uploadFile(driveId: Int,
                    directoryId: Int,
                    fileURL: URL,
                    fileName: String,
                    totalSize: Int64,
                    lastModifiedAt: Int?,
                    progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if totalSize >= Int64(Self.directUploadLimit) {
            try await uploadFileInChunks(driveId: driveId, directoryId: directoryId, fileURL: fileURL,
                                         fileName: fileName, totalSize: totalSize,
                                         lastModifiedAt: lastModifiedAt, progress: progress)
        } else {
            try await uploadFileDirect(driveId: driveId, directoryId: directoryId, fileURL: fileURL,
                                       fileName: fileName, totalSize: totalSize,
                                       lastModifiedAt: lastModifiedAt, progress: progress)
        }
    }

    private func uploadFileDirect(driveId: Int, directoryId: Int, fileURL: URL,
                                  fileName: String, totalSize: Int64, lastModifiedAt: Int?,
                                  progress: (@Sendable (Double) -> Void)?) async throws {
        var endpoint = APIEndpoint.upload(driveId: driveId)
        endpoint.query.append(URLQueryItem(name: "directory_id", value: String(directoryId)))
        endpoint.query.append(URLQueryItem(name: "file_name", value: fileName))
        endpoint.query.append(URLQueryItem(name: "total_size", value: String(totalSize)))
        endpoint.query.append(URLQueryItem(name: "conflict", value: "rename"))
        endpoint.query.append(URLQueryItem(name: "with", value: "capabilities,conversion_capabilities,sorted_name"))
        if let lastModifiedAt {
            endpoint.query.append(URLQueryItem(name: "last_modified_at", value: String(lastModifiedAt)))
        }
        let data = try await client.uploadFile(fileURL, endpoint: endpoint, progress: progress)
        try validateUpload(data)
    }

    private func uploadFileInChunks(driveId: Int, directoryId: Int, fileURL: URL,
                                    fileName: String, totalSize: Int64, lastModifiedAt: Int?,
                                    progress: (@Sendable (Double) -> Void)?) async throws {
        let totalChunks = max(1, Int((totalSize + Int64(Self.uploadChunkSize) - 1) / Int64(Self.uploadChunkSize)))

        struct StartSession: Encodable {
            let conflict: String
            let totalSize: Int64
            let fileName: String
            let totalChunks: Int
            let directoryId: Int
            let lastModifiedAt: Int?
            enum CodingKeys: String, CodingKey {
                case conflict
                case totalSize = "total_size"
                case fileName = "file_name"
                case totalChunks = "total_chunks"
                case directoryId = "directory_id"
                case lastModifiedAt = "last_modified_at"
            }
        }
        struct StartResponse: Codable {
            let token: String?
            let sessionToken: String?
            let uploadURL: String?
            enum CodingKeys: String, CodingKey {
                case token
                case sessionToken = "session_token"
                case uploadURL = "upload_url"
            }
        }

        let payload = StartSession(conflict: "rename", totalSize: totalSize, fileName: fileName,
                                   totalChunks: totalChunks, directoryId: directoryId,
                                   lastModifiedAt: lastModifiedAt)
        let body = try JSONEncoder().encode(payload)
        let startResponse: DataResponse<StartResponse> = try await client.send(
            APIEndpoint.startUploadSession(driveId: driveId), method: "POST", body: body,
            contentType: "application/json", cachePolicy: .reloadIgnoringLocalCacheData)
        guard let session = startResponse.data,
              let token = session.token ?? session.sessionToken,
              let uploadURLString = session.uploadURL,
              let uploadURL = URL(string: uploadURLString),
              Self.isTrustedUploadURL(uploadURL) else {
            throw APIError.invalidResponse
        }

        var progressFilter = UploadProgressFilter()
        do {
            let reader = try UploadChunkReader(fileURL: fileURL, chunkSize: Self.uploadChunkSize)
            for chunkIndex in 0..<totalChunks {
                let chunk = try reader.readChunk(at: chunkIndex)
                try await uploadChunk(driveId: driveId, token: token, host: uploadURL,
                                      chunkNumber: chunkIndex, data: chunk.data, hash: chunk.hash)
                let fraction = Double(chunkIndex + 1) / Double(totalChunks)
                if progressFilter.shouldReport(fraction) { progress?(fraction) }
            }
            try await finishUploadSession(driveId: driveId, token: token, host: uploadURL,
                                          lastModifiedAt: lastModifiedAt)
        } catch {
            try? await cancelUploadSession(driveId: driveId, token: token, host: uploadURL)
            throw error
        }
    }

    private func uploadChunk(driveId: Int, token: String, host: URL,
                             chunkNumber: Int, data: Data, hash: String) async throws {
        var endpoint = APIEndpoint.uploadChunk(driveId: driveId, token: token, host: host)
        endpoint.query.append(URLQueryItem(name: "chunk_number", value: String(chunkNumber)))
        endpoint.query.append(URLQueryItem(name: "chunk_size", value: String(data.count)))
        endpoint.query.append(URLQueryItem(name: "chunk_hash", value: "sha256:\(hash)"))

        struct ChunkResponse: Codable { let status: String? }
        var lastError: Error?
        for attempt in 1...Self.uploadChunkMaximumAttempts {
            do {
                let data = try await client.uploadData(data, endpoint: endpoint)
                let response = try? JSONDecoder().decode(DataResponse<ChunkResponse>.self, from: data)
                if response?.data?.status == "ok" { return }
                lastError = APIError.invalidResponse
            } catch {
                lastError = error
            }
            if attempt < Self.uploadChunkMaximumAttempts {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private func finishUploadSession(driveId: Int, token: String, host: URL, lastModifiedAt: Int?) async throws {
        var endpoint = APIEndpoint.finishUploadSession(driveId: driveId, token: token)
        if let lastModifiedAt {
            endpoint.query.append(URLQueryItem(name: "last_modified_at", value: String(lastModifiedAt)))
        }
        _ = try await client.uploadData(Data(), endpoint: endpoint)
    }

    private func cancelUploadSession(driveId: Int, token: String, host: URL) async throws {
        _ = try await client.dataRaw(
            APIEndpoint.cancelUploadSession(driveId: driveId, token: token), method: "DELETE",
            cachePolicy: .reloadIgnoringLocalCacheData)
    }

    /// Seuls les hôtes Infomaniak d'upload sont acceptés (sécurité).
    static func isTrustedUploadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "api.infomaniak.com"
            || host == "upload.kdrive.infomaniak.com"
            || host.hasSuffix(".upload.kdrive.infomaniak.com")
    }

    private func validateUpload(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        if let result = object["result"] as? String,
           !["success", "asynchronous"].contains(result) {
            throw APIError.invalidResponse
        }
        guard object["data"] != nil else { throw APIError.invalidResponse }
    }
}

/// Filtre de progression monotone (pas minimal de 0,01).
struct UploadProgressFilter {
    private var last = 0.0
    mutating func shouldReport(_ value: Double) -> Bool {
        guard value >= last + 0.01 || value >= 1 else { return false }
        last = value
        return true
    }
}

/// Lecteur de chunks avec calcul SHA-256.
final class UploadChunkReader {
    struct Chunk { let data: Data; let hash: String }
    private let handle: FileHandle
    private let chunkSize: Int
    private let totalSize: UInt64

    init(fileURL: URL, chunkSize: Int) throws {
        self.handle = try FileHandle(forReadingFrom: fileURL)
        self.chunkSize = chunkSize
        self.totalSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64 ?? 0
    }

    deinit { try? handle.close() }

    func readChunk(at index: Int) throws -> Chunk {
        let offset = UInt64(index) * UInt64(chunkSize)
        try handle.seek(toOffset: offset)
        let data = handle.readData(ofLength: chunkSize)
        return Chunk(data: data, hash: SHA256.hex(data))
    }
}
