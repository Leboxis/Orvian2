import Foundation

/// Erreurs normalisées de la couche API.
/// Structure d'erreur kDrive : `{ error: { code, description } }`.
enum APIError: LocalizedError {
    case notSignedIn
    case invalidURL
    case http(status: Int, code: String?, description: String?)
    case invalidResponse
    case decoding(Error, raw: Data?)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Aucun token configuré. Ouvrez l'onglet Plus pour le définir."
        case .invalidURL:
            return "URL invalide."
        case let .http(status, code, description):
            if status == 401 { return "Token invalide ou expiré (401)." }
            if status == 429 { return "Trop de requêtes vers le serveur (429). Réessayez dans un instant." }
            if let description, !description.isEmpty {
                if let code, !code.isEmpty { return "\(description) (HTTP \(status), \(code))" }
                return "\(description) (HTTP \(status))"
            }
            if let code, !code.isEmpty { return "Erreur serveur HTTP \(status) — \(code)." }
            return "Erreur serveur HTTP \(status)."
        case .invalidResponse:
            return "Réponse inattendue du serveur."
        case let .decoding(error, raw):
            var message = "Impossible d'interpréter la réponse du serveur."
            if let error = error as? DecodingError {
                message += " (champ : \(Self.decodingPath(of: error)))"
            }
            if let raw, let snippet = Self.firstElementSnippet(of: raw) {
                message += " — \(snippet)"
            }
            return message
        case let .network(error):
            return error.localizedDescription
        }
    }

    /// 401 uniquement : nécessite une déconnexion.
    var isUnauthorized: Bool {
        if case let .http(status, _, _) = self { return status == 401 }
        return false
    }

    /// Éligible à une stratégie de repli (fallback d'endpoint).
    var isFallbackCandidate: Bool {
        switch self {
        case let .http(status, _, _):
            return status == 403 || status == 404
        case .decoding, .invalidResponse:
            return true
        case .network, .notSignedIn, .invalidURL:
            return false
        }
    }

    var isOffline: Bool {
        if case .network = self { return true }
        return false
    }

    /// Convertit un `DecodingError` en chemin lisible `data[3].categories[0].categoryId`.
    static func decodingPath(of error: DecodingError) -> String {
        func pathString(_ path: [CodingKey]) -> String {
            var result = ""
            for key in path {
                if let index = key.intValue {
                    result += "[\(index)]"
                } else {
                    result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
            return result.isEmpty ? "racine" : result
        }
        switch error {
        case let .keyNotFound(key, context):
            return pathString(context.codingPath + [key])
        case let .valueNotFound(_, context):
            return pathString(context.codingPath)
        case let .typeMismatch(_, context):
            return pathString(context.codingPath)
        case let .dataCorrupted(context):
            return pathString(context.codingPath)
        @unknown default:
            return "inconnu"
        }
    }

    /// Extrait un extrait de `data[0]` (nom + catégories) tronqué à 400 caractères.
    static func firstElementSnippet(of raw: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
        let data = object["data"]
        let element: [String: Any]?
        if let array = data as? [[String: Any]] {
            element = array.first
        } else if let dictionary = data as? [String: Any] {
            element = dictionary
        } else {
            element = nil
        }
        guard let element else { return nil }
        var parts: [String] = []
        if let name = element["name"] { parts.append("data[0].name=\(name)") }
        if let categories = element["categories"] { parts.append("categories=\(categories)") }
        guard !parts.isEmpty else { return nil }
        let snippet = parts.joined(separator: " ")
        return String(snippet.prefix(400))
    }
}
