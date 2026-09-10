import Foundation

// MARK: - Enveloppes de réponse

/// Réponse paginée kDrive par curseur.
/// Vérifié : GET `/3/drive/{drive_id}/files/{file_id}/files` → `{ result, data, cursor, has_more }`.
struct CursorPage<T: Codable>: Codable {
    let result: String?
    let data: [T]
    let cursor: String?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case result, data, cursor
        case hasMore = "has_more"
    }
}

/// Réponse simple `{ result, data }`.
struct DataResponse<T: Codable>: Codable {
    let result: String?
    let data: T?
}

/// Compteurs d'un dossier : GET `/3/drive/{drive_id}/files/{file_id}/count`.
struct DirectoryCount: Codable, Hashable {
    let count: Int
    let files: Int
    let directories: Int
}

/// URL temporaire signée : GET `/2/drive/{drive_id}/files/{file_id}/temporary_url`.
struct TemporaryURL: Codable, Hashable {
    let temporaryURL: String

    enum CodingKeys: String, CodingKey {
        case temporaryURL = "temporary_url"
    }
}

struct InfomaniakAccount: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
}

struct Drive: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let size: Int?
    let usedSize: Int?
    let accountId: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case usedSize = "used_size"
        case accountId = "account_id"
    }
}

struct Category: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    /// Couleur possible en hex (String) ou entier ; normalisée en hex.
    let color: String?
    let isPredefined: Bool?
    let userUses: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case isPredefined = "is_predefined"
        case userUses = "user_uses"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        if let hex = try? container.decodeIfPresent(String.self, forKey: .color) {
            self.color = hex
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .color) {
            self.color = String(format: "#%06X", number & 0xFFFFFF)
        } else {
            self.color = nil
        }
        self.isPredefined = try? container.decodeIfPresent(Bool.self, forKey: .isPredefined)
        self.userUses = try? container.decodeIfPresent(Int.self, forKey: .userUses)
    }

    init(id: Int, name: String, color: String?, isPredefined: Bool?, userUses: Int?) {
        self.id = id
        self.name = name
        self.color = color
        self.isPredefined = isPredefined
        self.userUses = userUses
    }
}

/// Association fichier ↔ catégorie (avec décodage souple du `category_id`).
struct FileCategory: Codable, Hashable, Identifiable {
    let categoryId: Int
    let isGeneratedByAI: Bool?
    let userValidation: String?
    let userId: Int?
    let addedAt: Int?

    var id: Int { categoryId }

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case isGeneratedByAI = "is_generated_by_ai"
        case userValidation = "user_validation"
        case userId = "user_id"
        case addedAt = "added_at"
        case category, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var resolved: Int?
        resolved = try? container.decodeIfPresent(Int.self, forKey: .categoryId)
        if resolved == nil {
            resolved = try? container.decodeIfPresent(Int.self, forKey: .id)
        }
        if resolved == nil, let nested = try? container.decodeIfPresent(Category.self, forKey: .category) {
            resolved = nested.id
        }
        self.categoryId = resolved ?? -1
        self.isGeneratedByAI = try? container.decodeIfPresent(Bool.self, forKey: .isGeneratedByAI)
        self.userValidation = try? container.decodeIfPresent(String.self, forKey: .userValidation)
        self.userId = try? container.decodeIfPresent(Int.self, forKey: .userId)
        self.addedAt = try? container.decodeIfPresent(Int.self, forKey: .addedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(isGeneratedByAI, forKey: .isGeneratedByAI)
        try container.encodeIfPresent(userValidation, forKey: .userValidation)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(addedAt, forKey: .addedAt)
    }
}

// MARK: - Fichier

/// Fichier ou dossier kDrive. Décodage tolérant camelCase **et** snake_case.
struct DriveFile: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String
    let size: Int?
    let mimeType: String?
    let extensionType: String?
    let fileExtension: String?
    let isFavorite: Bool?
    let parentId: Int?
    let path: String?
    let color: String?
    let categories: [FileCategory]?
    let addedAt: Int?
    let lastModifiedAt: Int?
    let updatedAt: Int?
    let deletedAt: Int?

    static let rootType = "dir"

    var isDirectory: Bool { type == "dir" }
    var isImage: Bool {
        guard let mimeType else { return ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "bmp", "gif"].contains(fileExtension?.lowercased() ?? "") }
        return mimeType.hasPrefix("image/")
    }
    var isGIF: Bool {
        fileExtension?.lowercased() == "gif" || mimeType?.lowercased() == "image/gif"
    }
    var isVideo: Bool {
        if let mimeType, mimeType.hasPrefix("video/") { return true }
        return ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(fileExtension?.lowercased() ?? "")
    }
    var isPlainText: Bool {
        fileExtension?.lowercased() == "txt" || mimeType?.hasPrefix("text/plain") == true
    }

    var fileKind: FileKind {
        FileKind(extensionType: extensionType, mimeType: mimeType, fileName: name, isDirectory: isDirectory)
    }

    /// Recherche multi-mots, insensible à la casse et aux accents.
    func matchesSearchKeywords(_ keywords: [String]) -> Bool {
        guard !keywords.isEmpty else { return true }
        return keywords.allSatisfy { name.localizedStandardContains($0) }
    }

    static func root(name: String) -> DriveFile {
        DriveFile(id: 1, name: name, type: rootType, size: nil, mimeType: nil,
                  extensionType: nil, fileExtension: nil, isFavorite: nil, parentId: nil,
                  path: nil, color: nil, categories: nil, addedAt: nil,
                  lastModifiedAt: nil, updatedAt: nil, deletedAt: nil)
    }

    init(id: Int, name: String, type: String, size: Int?, mimeType: String?,
         extensionType: String?, fileExtension: String?, isFavorite: Bool?,
         parentId: Int?, path: String?, color: String?, categories: [FileCategory]?,
         addedAt: Int?, lastModifiedAt: Int?, updatedAt: Int?, deletedAt: Int?) {
        self.id = id
        self.name = name
        self.type = type
        self.size = size
        self.mimeType = mimeType
        self.extensionType = extensionType
        self.fileExtension = fileExtension
        self.isFavorite = isFavorite
        self.parentId = parentId
        self.path = path
        self.color = color
        self.categories = categories
        self.addedAt = addedAt
        self.lastModifiedAt = lastModifiedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, size, path, color, categories
        case mimeType = "mime_type"
        case extensionType = "extension_type"
        case fileExtension = "extension"
        case isFavorite = "is_favorite"
        case parentId = "parent_id"
        case addedAt = "added_at"
        case lastModifiedAt = "last_modified_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        // camelCase variantes
        case mimeTypeCamel = "mimeType"
        case extensionTypeCamel = "extensionType"
        case fileExtensionCamel = "fileExtension"
        case isFavoriteCamel = "isFavorite"
        case parentIdCamel = "parentId"
        case addedAtCamel = "addedAt"
        case lastModifiedAtCamel = "lastModifiedAt"
        case updatedAtCamel = "updatedAt"
        case deletedAtCamel = "deletedAt"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.type = (try? c.decode(String.self, forKey: .type)) ?? "file"
        self.size = try? c.decodeIfPresent(Int.self, forKey: .size)
        self.mimeType = Self.firstString(c, [.mimeType, .mimeTypeCamel])
        self.extensionType = Self.firstString(c, [.extensionType, .extensionTypeCamel])
        self.fileExtension = Self.firstString(c, [.fileExtension, .fileExtensionCamel])
        self.isFavorite = Self.firstBool(c, [.isFavorite, .isFavoriteCamel])
        self.parentId = Self.firstInt(c, [.parentId, .parentIdCamel])
        self.path = try? c.decodeIfPresent(String.self, forKey: .path)
        self.color = try? c.decodeIfPresent(String.self, forKey: .color)
        self.categories = try? c.decodeIfPresent([FileCategory].self, forKey: .categories)
        self.addedAt = Self.firstInt(c, [.addedAt, .addedAtCamel])
        self.lastModifiedAt = Self.firstInt(c, [.lastModifiedAt, .lastModifiedAtCamel])
        self.updatedAt = Self.firstInt(c, [.updatedAt, .updatedAtCamel])
        self.deletedAt = Self.firstInt(c, [.deletedAt, .deletedAtCamel])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(mimeType, forKey: .mimeType)
        try c.encodeIfPresent(extensionType, forKey: .extensionType)
        try c.encodeIfPresent(fileExtension, forKey: .fileExtension)
        try c.encodeIfPresent(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(categories, forKey: .categories)
        try c.encodeIfPresent(addedAt, forKey: .addedAt)
        try c.encodeIfPresent(lastModifiedAt, forKey: .lastModifiedAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    private static func firstString(_ c: KeyedDecodingContainer<CodingKeys>, _ keys: [CodingKeys]) -> String? {
        for key in keys { if let value = try? c.decodeIfPresent(String.self, forKey: key) { return value } }
        return nil
    }
    private static func firstInt(_ c: KeyedDecodingContainer<CodingKeys>, _ keys: [CodingKeys]) -> Int? {
        for key in keys { if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value } }
        return nil
    }
    private static func firstBool(_ c: KeyedDecodingContainer<CodingKeys>, _ keys: [CodingKeys]) -> Bool? {
        for key in keys { if let value = try? c.decodeIfPresent(Bool.self, forKey: key) { return value } }
        return nil
    }
}
