import Foundation

/// Endpoint kDrive : chemin + query.
/// Endpoints vérifiés dans `Api infomaniak.json`.
struct Endpoint {
    var path: String
    var query: [URLQueryItem]
    /// Hôte absolu optionnel (uploads chunkés sur un hôte dédié).
    var base: URL?

    init(path: String, query: [URLQueryItem] = [], base: URL? = nil) {
        self.path = path
        self.query = query
        self.base = base
    }

    /// Produit `name[]=valeur` répété (convention kDrive pour les tableaux).
    static func array(_ name: String, _ values: [String]) -> [URLQueryItem] {
        values.map { URLQueryItem(name: "\(name)[]", value: $0) }
    }

    /// Applique un tri kDrive : un `order_by[]` par champ + `order=asc|desc`.
    func ordering(_ orderBy: [String], order: String) -> Endpoint {
        var query = query.filter { $0.name != "order_by[]" && $0.name != "order" }
        query.append(contentsOf: Endpoint.array("order_by", orderBy))
        query.append(URLQueryItem(name: "order", value: order))
        return Endpoint(path: path, query: query, base: base)
    }
}

/// Catalogue exhaustif des endpoints utilisés. Base : `https://api.infomaniak.com`.
enum APIEndpoint {
    // MARK: Comptes / drives
    static func accounts() -> Endpoint { Endpoint(path: "/1/account") }
    static func drives(accountId: Int) -> Endpoint {
        Endpoint(path: "/2/drive", query: [URLQueryItem(name: "account_id", value: String(accountId))])
    }
    static func drive(driveId: Int) -> Endpoint { Endpoint(path: "/2/drive/\(driveId)") }

    // MARK: Listings (v3)
    static let listingWith = "is_favorite,categories,path"

    static func directoryContent(driveId: Int, directoryId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/\(directoryId)/files",
                 query: [URLQueryItem(name: "with", value: listingWith),
                         URLQueryItem(name: "limit", value: "60")])
    }
    static func directoryCount(driveId: Int, directoryId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/\(directoryId)/count")
    }
    static func lastModified(driveId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/last_modified",
                 query: [URLQueryItem(name: "with", value: listingWith),
                         URLQueryItem(name: "limit", value: "60")])
    }
    static func recents(driveId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/recents",
                 query: [URLQueryItem(name: "with", value: listingWith),
                         URLQueryItem(name: "limit", value: "60")])
    }
    static func activities(driveId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/activities",
                 query: [URLQueryItem(name: "with", value: listingWith),
                         URLQueryItem(name: "limit", value: "60")])
    }
    static func favorites(driveId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/favorites",
                 query: [URLQueryItem(name: "with", value: listingWith),
                         URLQueryItem(name: "limit", value: "60")])
    }
    static func search(driveId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/search")
    }
    static func fileInfo(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/\(fileId)",
                 query: [URLQueryItem(name: "with", value: listingWith)])
    }
    static func trashContent(driveId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/trash")
    }

    // MARK: Catégories (v2)
    static func categories(driveId: Int) -> Endpoint { Endpoint(path: "/2/drive/\(driveId)/categories") }
    static func category(driveId: Int, categoryId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/categories/\(categoryId)")
    }

    // MARK: Miniatures / médias (v2)
    static func thumbnail(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/files/\(fileId)/thumbnail")
    }
    static func trashedThumbnail(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/trash/\(fileId)/thumbnail")
    }
    static func temporaryURL(driveId: Int, fileId: Int, duration: Int = 3600) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/files/\(fileId)/temporary_url",
                 query: [URLQueryItem(name: "duration", value: String(duration))])
    }

    // MARK: Mutations
    static func favorite(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/files/\(fileId)/favorite")
    }
    static func fileCategory(driveId: Int, fileId: Int, categoryId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/files/\(fileId)/categories/\(categoryId)")
    }
    static func createFolder(driveId: Int, directoryId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/\(directoryId)/directory")
    }
    static func trash(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/files/\(fileId)")
    }
    static func permanentDelete(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/trash/\(fileId)")
    }
    static func restore(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/trash/\(fileId)/restore")
    }
    static func rename(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/files/\(fileId)/rename")
    }
    /// ÉCART SPEC : l'endpoint de couleur de dossier n'est pas listé dans `Api infomaniak.json`.
    /// Le code source d'Orvian utilise `POST /2/drive/{drive}/files/{file}/color` et la spec
    /// déclare la capacité `use_folder_custom_color` ; conservé tel quel en attendant confirmation.
    static func folderColor(driveId: Int, fileId: Int) -> Endpoint {
        Endpoint(path: "/2/drive/\(driveId)/files/\(fileId)/color")
    }
    static func move(driveId: Int, fileId: Int, destinationId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/files/\(fileId)/move/\(destinationId)")
    }

    // MARK: Upload (v3)
    static func upload(driveId: Int) -> Endpoint { Endpoint(path: "/3/drive/\(driveId)/upload") }
    static func startUploadSession(driveId: Int) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/upload/session/start")
    }
    static func uploadChunk(driveId: Int, token: String, host: URL) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/upload/session/\(token)/chunk", base: host)
    }
    static func finishUploadSession(driveId: Int, token: String) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/upload/session/\(token)/finish")
    }
    static func cancelUploadSession(driveId: Int, token: String) -> Endpoint {
        Endpoint(path: "/3/drive/\(driveId)/upload/session/\(token)")
    }
}
