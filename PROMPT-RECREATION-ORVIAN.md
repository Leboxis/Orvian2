# PROMPT DE RECRÉATION COMPLÈTE — ORVIAN

> Client iOS natif non officiel pour **kDrive (Infomaniak)** — Swift 5 + SwiftUI.
> Ce document est une spécification complète permettant de reconstruire l'application **de zéro**.

---

## RÈGLES PRIORITAIRES (à respecter en toutes circonstances)

### RÈGLE 1 — TOUJOURS SE RÉFÉRER À L'API OFFICIELLE

**Avant d'écrire ou de modifier la moindre ligne liée à kDrive/Infomaniak, consulte systématiquement la spécification OpenAPI officielle fournie dans le dépôt :**

- `Api infomaniak.json` (spec OpenAPI officielle Infomaniak/kDrive, à la racine du dépôt) — **source de vérité** pour : chemins exacts, versions (`/1/`, `/2/`, `/3/`), méthodes HTTP, paramètres/query, corps de requête, en-têtes, formats de réponse et d'erreur.
- Documentation en ligne : `https://developer.infomaniak.com/docs/api` et `https://developer.infomaniak.com` (création de token).

**Réflexes obligatoires :**
1. Ne jamais inventer un endpoint, un paramètre ou un champ : le vérifier d'abord dans `Api infomaniak.json`.
2. En cas de contradiction entre le code existant et la spec, **c'est la spec qui fait foi** ; signaler l'écart au lieu de suivre aveuglément le code.
3. Toujours respecter les conventions de l'API kDrive : `order_by[]`/`order`, `cursor`/`has_more`, `with=is_favorite,categories,path`, `conflict=rename`, uploads v3 (direct < 95 Mo / session chunkée ≥ 95 Mo, `sha256:<hash>`), `temporary_url`, etc.
4. Citer l'endpoint source (méthode + chemin) en commentaire pour toute intégration réseau.
5. Ne jamais forcer de paramètres non documentés (ex. dimensions de miniature, `total` sur `count`) : s'aligner sur le comportement documenté.
6. Vérifier les codes d'erreur et la structure `{ result, data }` / `{ error: { code, description } }` dans la spec avant d'implémenter la gestion d'erreurs.

### RÈGLE 2 — TOUJOURS CHOISIR LE MEILLEUR CHOIX QUI ÉLÈVE LES 3 PILIERS : UI / UX / DEV

À chaque décision technique, arbitrer **systématiquement** en faveur de l'option qui améliore les **trois** dimensions suivantes, sans en sacrifier une au profit d'une autre :

- **UI (interface)** : rendu visuel soigné, cohérent, matériaux natifs (`.ultraThinMaterial`, `.quaternary`), coins arrondis continus, ombres douces, animations fluides, cartes uniformes strictes, respect du design system `DS`.
- **UX (expérience)** : réactivité perçue (cache + préchargement, contenu conservé pendant le rechargement, mises à jour optimistes), gestes naturels (swipe, pinch, double-tap, swipe-to-dismiss), accessibilité (`accessibilityLabel`/`hint`/traits), feedback immédiat, états vides/erreur/chargement explicites, respect des réglages utilisateur, robustesse hors-ligne/trafic lent.
- **DEV (qualité d'ingénierie)** : isolation correcte (`@MainActor`, `actor`), zéro réseau/décodage sur le MainActor, concurrence bornée, annulation propre, déduplication/caches, découpage clair (View → ViewModel → Service → APIClient), tests, lisibilité, absence de dette technique, sécurité by design.

**Méthode de décision :**
1. Énoncer les options possibles.
2. Comparer leur impact sur UI, UX et DEV.
3. Choisir l'option qui maximise les trois ensemble (pas seulement la plus rapide à coder).
4. Si un compromis est inévitable, le rendre explicite et documenter le raisonnement.

### RÈGLE 3 — CRÉER UN `.env` ET NE JAMAIS LE PUBLIER

Créer un fichier **`.env.local`** (et/ou `.env`) contenant les secrets/identifiants de développement, par exemple :

```dotenv
# Secrets locaux — NE JAMAIS COMMITER
INFOMANIAK_API_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
INFOMANIAK_ACCOUNT_ID=12345
INFOMANIAK_DRIVE_ID=67890
```

**Obligations :**
1. **Ne jamais publier, commiter, pousser ou partager** le `.env`/`.env.local` ; il doit être listé dans `.gitignore`.
2. Aucun secret ne doit apparaître dans le code source, les tests, les logs, les captures ou la documentation.
3. Le token réel est fourni par l'utilisateur au premier lancement (colle dans l'onboarding) et stocké dans le **Keychain** (repli UserDefaults pour LiveContainer) — **jamais** en clair dans le dépôt.
4. Fournir un `.env.example` (valeurs fictives) versionnable pour documenter les variables attendues, sans secrets.
5. En CI, injecter les secrets via les *GitHub Secrets*, jamais dans les fichiers du dépôt.

---

## CONTEXTE ET OBJECTIF

Créer **Orvian**, un client iOS natif **non officiel** pour **kDrive (Infomaniak)**, en **Swift 5 + SwiftUI**, cible **iOS 26.0+**, iPhone et iPad. Expérience « Apple Photos » : grilles de miniatures fluides, visionneuse plein écran images/vidéos, lecteur AVPlayer quasi instantané. L'app doit tourner dans **LiveContainer** (aucun entitlement exotique, pas de BGTaskScheduler, IPA non signé), avec repli Keychain → UserDefaults.

**Contraintes d'architecture strictes :**
- Aucun appel réseau ni décodage d'image sur le MainActor.
- Vues-modèles `@MainActor @Observable` (macro Observation) ; tout le reste dans des `actor`/classes `Sendable`.
- Repository `KDriveService` (struct) au-dessus d'`APIClient` (`actor`, URLSession).
- Le projet Xcode est généré par **XcodeGen** depuis `project.yml` (pas de `.xcodeproj` commité).

```
View (SwiftUI) → ViewModel @MainActor @Observable → KDriveService (struct)
                                                   → APIClient (actor, URLSession)
                                                   → API kDrive v2/v3 (api.infomaniak.com)
```

---

## 1. `project.yml` (XcodeGen)

```yaml
name: Orvian
options:
  bundleIdPrefix: com.orvian
  createIntermediateGroups: true
  deploymentTarget: { iOS: "26.0" }
settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "0.8.161"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: true
    INFOPLIST_KEY_CFBundleDisplayName: Orvian
    INFOPLIST_KEY_UILaunchScreen_Generation: true
    INFOPLIST_KEY_UIApplicationSceneManifest_Generation: true
    INFOPLIST_KEY_UISupportedInterfaceOrientations: >-
      UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
    CODE_SIGNING_ALLOWED: "NO"
    CODE_SIGNING_REQUIRED: "NO"
targets:
  Orvian:
    type: application
    platform: iOS
    sources: [{ path: Orvian }]
    info:
      path: Orvian/Info.plist
      properties:
        UIBackgroundModes: [audio]          # lecture audio/vidéo en arrière-plan
        NSFaceIDUsageDescription: "Face ID sert à déverrouiller l'app sans saisir votre code."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.orvian.app
        TARGETED_DEVICE_FAMILY: "1,2"
schemes:
  Orvian:
    build: { targets: { Orvian: all } }
    run: { config: Debug }
    archive: { config: Release }
```

`.gitignore` doit exclure **au minimum** : `.env`, `.env.local`, `build/`, `*.xcodeproj`, `Payload/`, `*.ipa`.

---

## 2. COUCHE API

### 2.1 `Core/API/APIError.swift`

```swift
enum APIError: LocalizedError {
    case notSignedIn, invalidURL
    case http(status: Int, code: String?, description: String?)
    case invalidResponse
    case decoding(Error, raw: Data?)
    case network(Error)
}
```

Messages `errorDescription` exacts :
- `.notSignedIn` → « Aucun token configuré. Ouvrez l'onglet Plus pour le définir. »
- `.invalidURL` → « URL invalide. »
- `.http(401)` → « Token invalide ou expiré (401). »
- `.http(429)` → « Trop de requêtes vers le serveur (429). Réessayez dans un instant. »
- `.http` description non vide → `"<desc> (HTTP <status>[, <code>])"` ; sinon `"Erreur serveur HTTP <status>[ — <code>]."`
- `.invalidResponse` → « Réponse inattendue du serveur. »
- `.decoding` → « Impossible d'interpréter la réponse du serveur. » + `" (champ : <chemin>)"` + `" — <snippet>"`
- `.network` → `error.localizedDescription`

Propriétés : `isUnauthorized` (401 uniquement) ; `isFallbackCandidate` (403/404, `.decoding`, `.invalidResponse` → `true` ; réseau/401/429/notSignedIn/invalidURL → `false`).
`decodingPath(of:)` convertit un `DecodingError` en chemin type `data[3].categories[0].categoryId`. `firstElementSnippet(of:)` extrait `data[0].name=... categories=...` (tronqué à 400 car.).

### 2.2 `Core/API/Endpoints.swift`

`struct Endpoint { var path: String; var query: [URLQueryItem] }` avec :
- `static func array(_ name: String, _ values: [String]) -> [URLQueryItem]` → `name[]=valeur` répété.
- `func ordering(_ orderBy: [String], order: String) -> Endpoint` → supprime `order_by[]`/`order`, ajoute un `order_by[]` par champ + `order=asc|desc`.

**Catalogue exhaustif des endpoints** (base `https://api.infomaniak.com`) — **à vérifier dans `Api infomaniak.json`** :

| Nom | Méthode | Chemin | Notes |
|---|---|---|---|
| accounts | GET | `/1/account` | sans token autorisé (validation) |
| drives | GET | `/2/drive?account_id=` | |
| directoryContent | GET | `/3/drive/{d}/files/{dir}/files` | `with=is_favorite,categories,path`, `limit=60`, `order_by[]=type`, `order_by[]=name`, `order=asc`, `cursor` |
| directoryCount | GET | `/3/drive/{d}/files/{dir}/count` | rejette `total`, renvoie count/files/directories |
| lastModified | GET | `/3/drive/{d}/files/last_modified` | `with`, `limit=60`, `cursor` |
| recents | GET | `/3/drive/{d}/files/recents` | idem |
| activities | GET | `/3/drive/{d}/files/activities` | entrée contient le fichier sous clé `file` |
| favorites | GET | `/3/drive/{d}/files/favorites` | |
| categoryFiles | GET | `/3/drive/{d}/files/search` | `category={id}`, `depth=unlimited`, pas d'`order_by` |
| search | GET | `/3/drive/{d}/files/search` | `query` (trim, si non vide), `directory_id`, `depth=unlimited` |
| fileInfo | GET | `/3/drive/{d}/files/{f}` | `with=is_favorite,categories,path` |
| trashContent | GET | `/3/drive/{d}/trash` | |
| categories | GET/POST | `/2/drive/{d}/categories` | GET liste, POST crée |
| category | PUT/DELETE | `/2/drive/{d}/categories/{c}` | |
| thumbnail | GET | `/2/drive/{d}/files/{f}/thumbnail` | ne pas forcer de dimensions |
| trashedThumbnail | GET | `/2/drive/{d}/trash/{f}/thumbnail` | |
| restore | POST | `/2/drive/{d}/trash/{f}/restore` | corps `{"destination_directory_id": …}` |
| temporaryURL | GET | `/2/drive/{d}/files/{f}/temporary_url?duration=3600` | |
| favorite | POST/DELETE | `/2/drive/{d}/files/{f}/favorite` | |
| fileCategory | POST/DELETE | `/2/drive/{d}/files/{f}/categories/{c}` | |
| createFolder | POST | `/3/drive/{d}/files/{dir}/directory` | corps `{"name": …}` |
| upload | POST | `/3/drive/{d}/upload` | `directory_id`, `file_name`, `total_size`, `last_modified_at`, `conflict=rename`, `with=capabilities,conversion_capabilities,sorted_name`, corps brut |
| startUploadSession | POST | `/3/drive/{d}/upload/session/start` | |
| uploadContent | POST | `/3/drive/{d}/upload` | `file_id`, `total_size`, `last_modified_at` (nouvelle version) |
| finishUploadSession | POST | `/3/drive/{d}/upload/session/{token}/finish` | |
| cancelUploadSession | DELETE | `/3/drive/{d}/upload/session/{token}` | |
| trash | DELETE | `/2/drive/{d}/files/{f}` | vers corbeille |
| permanentDelete | DELETE | `/2/drive/{d}/trash/{f}` | |
| rename | POST | `/2/drive/{d}/files/{f}/rename` | `{"name": …}` |
| updateFolderColor | POST | `/2/drive/{d}/files/{f}/color` | `{"color": "#rrggbb"}` |
| move | POST | `/3/drive/{d}/files/{f}/move/{dest}` | destination dans le chemin |

### 2.3 `Core/API/APIClient.swift` (actor)

- `static let shared`, `static let baseURL = URL(string: "https://api.infomaniak.com")!`
- Session `apiConfiguration` : `URLCache(memoryCapacity: 20 Mo, diskCapacity: 150 Mo, diskPath: "api-url-cache")`, `httpMaximumConnectionsPerHost = 8`.
- `request(...)` : base URLComponents + path + query, `httpMethod`, `timeoutInterval = 30`, `Accept: application/json`, `Authorization: Bearer <token>` si présent. Auth requise sauf si path commence par `/1/`.
- **Coalescing des GET** : `inFlightGETs: [String: Task<Data,Error>]`, clé `"<fingerprint|anon>|<cachePolicy.rawValue>|<url>"`. Les GET profitent du cache/ETag (`.useProtocolCachePolicy`) ; mutations en `.reloadIgnoringLocalCacheData`.
- `check(response:data:credentialFingerprint:)` : sur statut hors `200..<300`, poste **`.apiUnauthorized`** sur MainActor (objet = fingerprint SHA-256 du token) si 401 + fingerprint connu, puis lève `APIError.http(...)`. `decodeError` lit `{error:{code,description}}`.
- `JSONDecoder.api` : `keyDecodingStrategy = .useDefaultKeys`.
- **Upload** : `timeoutInterval = 300`, `UploadProgressDelegate` (NSObject, `URLSessionDataDelegate`) + `OperationQueue` max 1, `URLSession` dédiée, `finishTasksAndInvalidate()`. `withTaskCancellationHandler` crée la tâche **avant** d'enregistrer l'annulation. `uploadFile` via `uploadTask(fromFile:)` (streaming disque) ; `uploadData` via `from: data`. Suit les redirections **uniquement** si `isTrustedUploadURL`.
- **`isTrustedUploadURL`** : `https` + hôte `api.infomaniak.com`, `upload.kdrive.infomaniak.com`, ou suffixe `.upload.kdrive.infomaniak.com`. Sinon refus.
- `CacheProbeDelegate` : `fromCache = true` si une transaction `resourceFetchType == .localCache` ou statut 304.
- Notification : `Notification.Name.apiUnauthorized = "com.orvian.api.unauthorized"`.

### 2.4 `Core/API/KDriveService.swift` (struct)

Constantes : `directUploadLimit = 95 * 1024 * 1024`, `uploadChunkSize = 20 * 1024 * 1024`, `uploadChunkMaximumAttempts = 3`, `browsableOrderingFields = ["added_at","last_modified_at","mime_type","name","revised_at","size","type","updated_at"]`.

```swift
enum FileSource: Hashable {
    case directory(Int)
    case favorites(limit: Int = 60)
    case recents(limit: Int = 12)
    case category(Int)
    case trash
    case search(query: String, directoryId: Int?)
    static var favorites: FileSource { .favorites() }
}
```

Méthodes : `accounts()`, `drives(accountId:)`, `discoverDrives() -> (accountId, [Drive])` (parcourt les comptes, retourne le premier avec des drives), `page(_ source:driveId:cursor:orderBy:order:forceNetwork:)`, `fileInfo`, `directoryCount`, `categories`, `createCategory`, `updateCategory`, `deleteCategory`, `addCategory`, `removeCategory`, `setFavorite`, `temporaryURL`, `thumbnailData(isTrashed:)` (toujours `.reloadIgnoringLocalCacheData`), `createFolder`, `uploadContent`, `uploadFile`, `trash`, `permanentlyDelete`, `restore`, `rename`, `setFolderColor`, `move`.

**`page` :** `forceNetwork` → `.reloadIgnoringLocalCacheData`. Aiguillage selon `source` avec listes de champs `order_by` autorisées. `safeOrdering` : si un champ demandé n'est pas supporté (après alias), **renvoie l'endpoint inchangé** (jamais de 400).

**Cascade `recents` (4 niveaux)** : `/files/last_modified` → `/files/recents` → `/files/activities` (dédup par `id`) → `/files/search?query=`. Ne continue que si `APIError.isFallbackCandidate` (403/404/decoding/invalidResponse) ; s'arrête sur réseau/401/429.

**`uploadFile`** : si `totalSize >= 95 Mo` → chunks. Direct : `POST .upload` avec `conflict=rename`, valide `result ∈ {nil,"success","asynchronous"}` et `data != nil`.

**`uploadFileInChunks`** : `totalChunks = max(1, ceil(size/20Mo))` ; `StartUploadSessionRequest {conflict:"rename", total_size, file_name, total_chunks, directory_id, last_modified_at}` ; valide `session.token ?? session_token`, `upload_url` (hôte de confiance) ; `UploadChunkReader` (FileHandle + SHA-256 hex) lit 20 Mo ; URL de chunk = `/3/drive/{d}/upload/session/{token}/chunk` sur l'hôte renvoyé, query `chunk_number`, `chunk_size`, `chunk_hash=sha256:<hash>` ; `uploadChunk` jusqu'à 3 tentatives, backoff `sleep(attempt)` s ; valide `chunk.status == "ok"` ; `finish` avec `last_modified_at` ; en erreur → `DELETE .../cancel` best-effort.

### 2.5 Modèles

**`DriveFile`** (`Codable, Identifiable, Hashable`) : `id`, `name`, `type` ("dir"/"file") obligatoires ; `size`, `mimeType`, `extensionType`, `fileExtension` (clé `extension`), `isFavorite`, `parentId`, `path`, `color`, `categories: [FileCategory]?`, `addedAt`, `lastModifiedAt`, `updatedAt` optionnels. Décodage custom tolérant camelCase **et** snake_case. Encodage en snake_case. Computed : `isDirectory`, `isImage`, `isGIF` (extension/`fileExtension`/mime `image/gif`), `isVideo`, `isPlainText`, `fileKind`, `matchesSearchKeywords` (tous les mots, `localizedStandardContains`). `static func root(name:)` → `id=1, type="dir"`.

**`CursorPage<T>`** : `result`, `data`, `cursor`, `hasMore` (`has_more`). **`DirectoryCount`** : `count`, `files`, `directories` (non optionnels). **`DataResponse<T>`** : `result`, `data`. **`TemporaryURL`** (`temporary_url`). **`InfomaniakAccount`** : `id`, `name?`. **`Drive`** : `id`, `name`, `size?`, `usedSize?` (`used_size`), `accountId?` (`account_id`). **`Category`** : `id`, `name`, `color?`, `isPredefined?`, `userUses?`. **`FileCategory`** : `categoryId` (résolu depuis `categoryId`/`category_id`/`category.id`/`id`, sinon `-1`), `isGeneratedByAi?`, `userValidation?`, `userId?`, `addedAt?`.

### 2.6 `Models/FileFilters.swift`

```swift
struct FileFilters: Equatable, Hashable {
    enum SortMode: String, CaseIterable { original, modifiedDate, addedDate, type, size, duration }
    enum Direction: String, CaseIterable { ascending, descending }
    enum Orientation: String, CaseIterable, Codable { portrait, landscape, square }
    enum MediaFilter: String, CaseIterable { all, videos, images, other }
    var sort: SortMode = .original
    var direction: Direction = .descending
    var orientation: Orientation? = nil
    var highResolutionVideosOnly = false
    var media: MediaFilter = .all
}
```

- `serverOrderBy` : `.original`/`.duration` → nil ; `.modifiedDate` → `["updated_at"]` ; `.addedDate` → `["added_at"]` ; `.type` → `["type"]` ; `.size` → `["size"]`.
- `serverOrder` : `desc` | `asc`. `isActive` : sort ≠ original OU orientation OU 4K+ OU media ≠ all.
- `visible(_:searchText:mediaMetadata:)` : filtre média → orientation (nécessite métadonnées vidéo) → 4K+ → recherche mots-clés → tri local.
- Tri : valeurs manquantes `-.infinity` (dates) / `-1` (taille/durée) ; départage par nom (`localizedStandardCompare`, toujours croissant) puis par `id`. Seuil 4K : `maximumDimension >= 3840`.

---

## 3. AUTH & SÉCURITÉ

### 3.1 `TokenStore` (enum statique)
- Clés : Keychain service `com.orvian.app.api-token`, account `orvian` ; repli UserDefaults `orvian.api-token.fallback`. `kSecAttrAccessibleAfterFirstUnlock`.
- `current()`, `save(_:)` (trim, Keychain sinon repli), `clear()`, `credentialFingerprint()` (SHA-256 hex minuscule), `fingerprint(of:)`. `NSLock` + cache mémoire.

### 3.2 `AppLockStore` (enum statique)
- Même schéma : service `com.orvian.app.applock`, account `lock-code`, repli `orvian.applock.fallback`.
- Ne stocke que le SHA-256 via `TokenStore.fingerprint(of:)`. `isConfigured`, `verify(_:)`, `save(_:)`, `clear()`. Code à 4 chiffres imposé par les vues.

### 3.3 `SessionStore` (`@MainActor @Observable`)
- `enum Phase { signedOut, bootstrapping, signedIn, error(String) }`.
- Propriétés `private(set)` : `phase`, `drives`, `accountId`, `selectedDrive`, `signedOutMessage`. Clés UserDefaults `orvian.account-id`, `orvian.drive-id`. Message `expiredSessionMessage`.
- `bootstrap()` : si token absent → `.signedOut` ; sinon `.bootstrapping` → `loadDrives(preferred:)` → `.signedIn`, ou 401 → `clearSession(expired)`, sinon `.error`.
- `signIn(token:)` : purge `DirectoryListStore`/`CategoryLibrary`, `TokenStore.save`, chargement drives, guard drive sélectionné.
- `signOut()`, `handleUnauthorized(credentialFingerprint:)` (ignore si fingerprint ≠ token courant).
- `clearSession(message:)` ordre : `UploadManager.cancelAllAndClear()` → `DirectoryListStore.clear()` → `CategoryLibrary.clear()` → `TokenStore.clear()` → reset defaults/état → `.signedOut`.
- `selectDrive(_:)`, `reloadDrives()`.

---

## 4. CACHES & RÉSEAU

### 4.1 `ThumbnailProvider` (actor)
- Cache mémoire **statique** `NSCache<NSString,UIImage>` (`countLimit 600`, coût max 80 Mo), coût `w*h*4`.
- `AsyncThrottler(maxConcurrent: 9)`, `inFlight` dédup par `(driveId,fileId)`, file de prefetch max 6.
- Retries post-upload `[.zero, 2, 3, 5, 8, 12, 15, 15]` s (~60 s) via `thumbnailWhenAvailable` ; cache négatif `recentFailures` TTL 300 s, borne 512.
- API : `cachedMemoryThumbnail` (nonisolated synchrone), `thumbnail`, `thumbnailWhenAvailable`, `primeUploadedThumbnail`, `prefetch`, `cancelPrefetch`, `purgeDiskCache`, `diskCacheSize`, `enforceDiskLimit`.
- Décodage `UIImage(data:)?.preparingForDisplay()` ; `decodeAndStore` et `loadFromDisk` `nonisolated async`.

### 4.2 `DiskImageCache` (final class `@unchecked Sendable`)
- Dossier `Library/Caches/thumbnails/<driveId>/<fileId>.jpg`, legacy `-360.jpg`.
- Limite lue `UserDefaults "thumbnailCacheLimitMB"` (défaut 250 Mo ; ≤0 = illimité) ; bas = 80 %. Éviction **Oldest-Written** en `Task.detached(.utility)` ; scan toutes les 150 écritures ; génération de purge.
- `hasEntry`, `loadImage`, `removeEntry`, `store(data:)` (`.atomic`), `purge`, `totalSize`, `enforceSizeLimit`.

### 4.3 `DirectoryListStore` (`@MainActor`, singleton)
- `DirectoryListSnapshot: Codable { items, cursor, hasMore, totalItemCount, orderBy, order, fetchedAt }`.
- TTL 300 s, capacité 50. Clé = `<credentialFingerprint>|<driveId>|<type>|<id>|<ordering>` ; `.search` → `nil` (jamais caché).
- `snapshot`, `store`, `diskSnapshot`, `mergeRecentUploads`, `clear`. Persistance disque uniquement pour `.favorites`/`.recents` (`isPersistedList`).

### 4.4 `FavoritesDiskCache` (final class)
- File série `com.orvian.favorites-cache` ; dossier `Caches/OrvianFavorites` ; `Entry{version,key,snapshot}` ; JSON.
- `maximumAge` 7 j, fichier max 2 Mo, total max 10 Mo, max 20 fichiers. Nom = SHA-256(clé).json. Écriture `.atomic` + `completeFileProtectionUntilFirstUserAuthentication`. Corrompu/expiré → supprimé + `nil`. `clear()`.

### 4.5 `RecentUploadsLoader` (`@MainActor`)
- `source = .recents(limit: 12)`, revalidation 60 s, dédup réseau par drive, protège les uploads locaux récents. `cachedSnapshot`, `refresh(forceNetwork:)`, `prefetch`.

### 4.6 `AsyncThrottler` (`@unchecked Sendable`)
- `init(maxConcurrent:)`, `withPermit` via `withCheckedContinuation`, un seul verrou pour acquérir/libérer (évite permis perdu). `ThumbnailProvider` = 9, `HiresImageStore` = 2.

### 4.7 `NetworkMonitor` (`@unchecked Sendable`, `NWPathMonitor`)
- `allowsBackgroundPrefetch` : vrai uniquement si Wi-Fi confirmé (sinon `false`).

### 4.8 `Perf` / `PerfTimer` (`@MainActor ObservableObject`)
- `Entry{method,path,status,durationMs,bytes,fromCache}`, `endpointName` (dernier segment, numérique → `resource/{id}`), `isThumbnail` (`/thumbnail`). Journal borné 400 ; `entries` exclut les miniatures ; `statsByEndpoint` ; clé `UserDefaults "networkPerfEnabled"` (absent = activé). Signpost `com.orvian.perf`.

---

## 5. MÉDIAS

### 5.1 `MediaURLCache` (actor)
- Clé `{driveId, fileId, credentialFingerprint}`. TTL effectif 3300 s, marge 30 s. Dédup `inFlight`. `url`, `freshURL`, `invalidate`, `prefetch` (2 simultanés), `cancelPrefetch`.

### 5.2 `HiresImageStore` (actor)
- `NSCache` (`countLimit 3`, coût max 192 Mo), dédup `"driveId-fileId"`, `AsyncThrottler(maxConcurrent: 2)`.
- `image(driveId:fileId:)` : `URLSession.shared.download` → ImageIO (`CGImageSourceCreateThumbnailAtIndex` index 0, `FromImageAlways`, `WithTransform`, `ShouldCacheImmediately`) → `UIImage(cgImage:)`.
- `static decodeOriginal(fromFile:)`.

### 5.3 `GIFImageStore` (actor)
- `GIFFrame{image:CGImage, delay:Double}`, `GIFImage{firstFrame, frameCount, loopCount, source, aspectRatio}`, `GIFFrameSource` (actor, `frame(at:)` à la demande, supprime le fichier au `deinit`).
- Délai : `kCGImagePropertyGIFUnclampedDelayTime` sinon `DelayTime`, défaut 0,1, plancher 0,02. Type UTI exact `com.compuserve.gif`. Un seul téléchargement ; seules première + courante + suivante en mémoire.

### 5.4 `MediaMetadataStore` (`@MainActor ObservableObject`)
- `Info{duration, orientation, maximumDimension, is4KOrAbove}`. Mémoire `[Int:Info]`, disque `Application Support/Orvian/video-metadata.json` (clé `"driveId-fileId"`, `PersistedEntry`), limite 6000 (réduit à 3000 au-delà), sauvegarde coalescée 1 s.
- `resolveAll(driveId:items:)` par lots de 8 ; `videoProperties` : orientation si ratio < 1.15 → carré, sinon paysage/portrait ; `is4KOrAbove` si ≥ 3840.

### 5.5 `VideoAssetCache` (`@MainActor`)
- LRU 8 entrées, clé `{driveId,fileId,fingerprint}`, `asset(driveId:fileId:)` (vérifie `https` + host), `prefetch` (load `.isPlayable`), `cancelPrefetch`, `invalidate` (invalide aussi `MediaURLCache`).

---

## 6. UPLOAD & TÉLÉCHARGEMENT

### 6.1 `UploadManager` (`@MainActor @Observable`, singleton)
```swift
enum UploadStatus: Equatable { case queued; case inProgress(progress: Double); case completed; case failed(message: String) }
struct UploadTaskItem: Identifiable, Equatable { let id: UUID; var fileName; var totalBytes; var status; let date }
struct UploadPayload: Sendable { let fileURL; let fileName; let totalBytes; let isTemporary }
```
- `maxConcurrentUploads = 4`. `enqueuePhotos(driveId:directoryId:items:onDone:)`, `enqueueDocuments(...urls...)`, `cancelAllAndClear()`, `clearCompleted()`.
- Progression : préparation 0,15 → 0,2, puis `0,2 + fraction*0,8` ; filtre monotone `UploadProgressFilter` (pas 0,01).
- Noms : photos provisoires « Photo.ext » / « Média N.ext », réels « Import-<timestamp>-<n>.ext » ; documents = `lastPathComponent`.
- Photos via `PhotosPickerItem`, `PickedPhotoTransferable: Transferable` (copie dans `temp/Uploads/<UUID>_<nom>`). Fichiers via `DocumentPicker` (`asCopy: true`).
- Pill auto-masquée après 5 s si plus d'actifs et pas d'échec. `activeTasksCount`, `completedTasksCount`, `hasFailures`, `overallProgress`.
- Après upload : `mergeUploaded`, `DirectoryListStore.mergeRecentUploads`, `FileGridMutationCenter.publish(.uploaded)` ; miniature si `supportsThumbnail` (`primeUploadedThumbnail`).

### 6.2 `FileDownloadService` (`@MainActor ObservableObject`, singleton)
- `downloadAndShare(driveId:file:)` : URL temporaire → `URLSession` download avec progression (pas 0,01) → `temp/OrvianDownloads/<UUID>/` → `UIActivityViewController` (popover centré). Sur statut `[401,403,404,410]` → rafraîchit l'URL et retente **une fois**.
- Nom sûr : retire contrôle `/ \ :`, limite 200 octets UTF-8, extension max 24 octets. `cancelDownload()`, `errorMessage`, `progress`, `isDownloading`, `downloadingFileName`.

---

## 7. UTILITAIRES

- **`FileKind`** : `enum String, CaseIterable { folder, image, video, audio, pdf, text, spreadsheet, presentation, archive, code, other }`. `init(extensionType:mimeType:fileName:isDirectory:)` : dossier → folder ; puis type fonctionnel ; puis MIME ; puis extension. `supportsThumbnail` (image/video/pdf), `symbolName`, `label`, `tint` (couleurs RGB précises listées ci-dessus).
- **`ByteFormatter`** : `ByteCountFormatter(.file, adaptive)`, « — » si nil/négatif ; `string`, `format`, `usage(used:total:)`.
- **`CategoryLibrary`** (`@MainActor @Observable`) : `categoriesByDrive`, générations de session/refresh, `ensureLoaded`, `refresh`, `upsert`, `remove`, `clear`.
- **`TagOrderStore`** : UserDefaults `tag-order-<driveId>`, `order(for:)` (nil si vide), `save`.
- **`BoundedConcurrency`** : `mapBounded(items, concurrency:, operation:)` par lots, résultats ordonnés.
- **`Color+Hex`** : `init?(hex:)` (3/6 chiffres, `#` optionnel), `toHex()`.
- **`Perf`, `PerfTimer`** : voir 4.8.

---

## 8. APPLICATION & NAVIGATION

### 8.1 `OrvianApp`
- `@State session = SessionStore()`. Dans `init`, relève `URLCache.shared` (20 Mo mémoire / 150 Mo disque). `WindowGroup { RootView(session:) .task { await session.bootstrap() } }`.

### 8.2 `RootView`
- Verrou si `AppLockStore.isConfigured && !isUnlocked` → `AppLockView`. Sinon selon `session.phase` : `TokenSetupView`, `BootSplash`, `BootstrapError`, ou `MainTabView` (`.id(drive.id)` pour reconstruire au changement de drive).
- `onReceive(.apiUnauthorized)` → `handleUnauthorized`. `onChange(scenePhase)` : `.background` → `isUnlocked = false`, `hasGoneBackground = true`.
- `AppMark` : monogramme dégradé bleu→violet (rect arrondi 24 + cercles + triangle), 88×88, ombre.

### 8.3 `MainTabView`
- `ZStack(alignment: .bottom)` : `tabs` + empilement `DownloadProgressBanner` (si `isDownloading`) + `UploadProgressPill` (si `isPillVisible`) + `FloatingTabBar`.
- Onglets montés : **seul Accueil reste monté en permanence** ; les autres recréés à la visite. Navigation portée par `TabNavigationState`.
- `.fullScreenCover` pour `MediaPagerView` (router.mediaContext) et `TextFileViewer` (router.textFile). Alerte d'erreur de téléchargement. Au clic sur Profil → `RecentUploadsLoader.prefetch`.

### 8.4 `TabNavigationState` (`@MainActor @Observable`)
- `homePath`, `favoritesPath`, `favoritesScrollToTopRequest`, `tagsPath: NavigationPath`, `tagsTrail`, `profilePath`, `profileRefreshRequest`, `settingsPath`. `reset(tab:scrollFavoritesToTop:)`.

---

## 9. ONGLETS (barre flottante, gauche→droite)

`AppTab` : **Réglages** (`gearshape`), **Tag** (`tag`), **Accueil** (`house`), **Favoris** (`star`), **Profil** (`person`).

### 9.1 Accueil (`HomeTab` + `DirectoryView`)
- `HomeTab` résout le **premier dossier de la racine** (`page(.directory(1))`) et l'utilise comme racine du `NavigationStack` ; la racine technique n'est jamais empilée. Cache UserDefaults `home_start_dir_locked_<driveId>` pour affichage instantané ; revalidation réseau au lancement ; repli `DriveFile.root(name:"Accueil")`.
- `DirectoryView` (réutilisé par Favoris et Tag) : `FileGridView` + breadcrumb capsule (`crumbs.joined("  ›  ")`), barre de recherche (révélée au scroll, `alwaysShowSearch`, debounce 300 ms, portée dossier/drive via `searchRestrictedToFolder`), bouton dé aléatoire, sélection multiple (tags, déplacement, suppression), bouton « + » flottant `AddMenuButton`, indicateur d'occupation.
- Actions toolbar : filtre (gauche), titre (crumb), dés + Sélectionner (droite) ; en sélection : tout sélectionner, tag, déplacer, corbeille.

### 9.2 Tag (`TagsView`)
- Grille ou liste de catégories (`tagsLayout`, `tagGridColumns`), compteur `userUses`, réordonnancement par drag (`TagOrderStore`), création (`CreateTagSheet` : nom + palette 18 couleurs + ColorPicker), renommage, suppression (`confirmationDialog`). Context menus. `CategoryFilesView` → `FileGridView(source: .category(id))` avec dossiers d'abord si réglage.
- `TagGridCard`, `CategoryRow`, `TagPalette`, `TagReorderDropDelegate`.

### 9.3 Favoris (`FavoritesView`)
- `FileGridView(source: .favorites)` dans un `NavigationStack(path:)` ; navigation dans les dossiers favoris. Toolbar filtre. `scrollToTopRequest` (second appui sur l'onglet). Badge favori masqué dans cet onglet.

### 9.4 Réglages (`SettingsView`)
Cartes dans l'ordre, avec toutes les clés `@AppStorage` :

| Réglage | Clé | Défaut |
|---|---|---|
| Résumé du drive + Changer (si >1 drive) + progression | — | — |
| Afficher le poids des fichiers | `showFileSizes` | true |
| Cartes par ligne (2–7) | `fileGridColumns` | 3 |
| Colonnes des tags (2/3) | `tagGridColumns` | 2 |
| Dossiers en premier dans les tags | `foldersFirstInTags` | true |
| Recherche toujours visible | `alwaysShowSearch` | false |
| Couleur par défaut des dossiers | `defaultFolderColor` | `#4285F5` |
| Revenir en haut dans les favoris | `favoritesReselectScrollToTop` | true |
| Précharger les miniatures | `prefetchThumbnails` | true |
| Précharger les vidéos | `prefetchVideoURLs` | true |
| Précharger seulement en Wi-Fi | `prefetchOnWiFiOnly` | false |
| Limite cache (250/500/1024 Mo, 0=illimité) | `thumbnailCacheLimitMB` | 250 |
| Vider le cache | — | — |
| Retours haptiques | `hapticFeedbackEnabled` | true |
| Suivi des requêtes réseau | `networkPerfEnabled` | true |
| Sécurité (activer/modifier/désactiver code) | AppLockStore | — |
| Compte (changer token / se déconnecter) | — | — |

Effets : `onChange` annule les prefetchs correspondants, applique la limite de cache (`enforceDiskLimit`). `DrivePickerSheet` (coche le drive courant). Sheets AppLock `.activate/.change/.disable`.

### 9.5 Profil (`ProfileView`)
- Sections : **Uploads récents** (3 miniatures, `RecentUploadsLoader`, NavigationLink vers `RecentFilesView(source: .recents(limit:12))`), **Stockage** (→ `TrashView`), **À propos** (version, → `PerfView`).
- `ProfileThumbnailCard` (badge play vidéo, context menu Télécharger), `AsyncProfileThumbnail`. Second appui sur l'onglet → `loadPreviews(forceNetwork: true)`.

### 9.6 Corbeille (`TrashView`)
- `FileGridView(source: .trash)` ; tap → `confirmationDialog` « Restaurer / Restaurer et ouvrir / Supprimer définitivement ». Sélection multiple : tout sélectionner, restaurer, supprimer. `restore` vers `parentId ?? 1` (retente à 1). `permanentlyDelete`.

### 9.7 Onboarding (`TokenSetupView`)
- `AppMark`, titre « Orvian », `SecureField` token (≥ 20 caractères), bouton « Se connecter », note Keychain, « Où trouver mon token ? » (`TokenHelpSheet`, detents `.medium`, lien developer.infomaniak.com). `session.signIn`.

### 9.8 Sécurité (`AppLockView`, `AppLockSetupSheet`, `CodeEntryControls`)
- `AppLockView` : monogramme (tap = biométrie), titre « Orvian verrouillé », `CodeDots` (4), `CodeKeypad` 3×4, `ShakeEffect`. Biométrie `LAContext` `.deviceOwnerAuthenticationWithBiometrics` (auto au retour d'arrière-plan). Vérification à 4 chiffres ; échec → shake + reset 0,85 s.
- `AppLockSetupSheet` : flows `activate`/`change`/`disable`, stages `verifyCurrent`/`enterNew`/`confirmNew`, textes FR exacts, délais 0,85 s/2,4 s. `interactiveDismissDisabled(!code.isEmpty)`.
- `CodeDots` (cercles 18×18, scale 1.12 en cours), `CodeKeypad` (touches 76×64, `KeypadButtonStyle`), `ShakeEffect` (travel 9, 3 shakes/unité), `AppLockHaptics` (respecte `hapticFeedbackEnabled`).

---

## 10. GRILLES ET CARTES (cœur de l'app)

### 10.1 `FileGridView` (composant réutilisable)
Paramètres : `viewModel`, `grouping`, `onOpenDirectory`, `onOpenFile`, `onVisibleItemsChanged`, `searchText`, `filters`, `onScrolledPastTop`, `contentTopInset`, `allowsPullToRefresh`, `selectionMode`, `selectedIDs`, `onToggleSelection`, `onMove`, `scrollToTopRequest`.

- **Grille** : `LazyVGrid` avec `min(max(fileGridColumns,2),7)` colonnes `GridItem(.flexible(), spacing: DS.gridSpacing)`.
- **Pagination** : à l'apparition de l'index `>= count - 6` → `loadMoreIfNeeded`. Squelette 9 cartes. Pull-to-refresh sauf Accueil.
- **Préchargement** : 3 cartes suivantes, miniatures (si `prefetchThumbnails`) et URLs vidéo (`prefetchVideoURLs`), delai 180 ms, gate Wi-Fi (`prefetchOnWiFiOnly`). `VideoAssetCache.prefetch` (corbeille exclue).
- **Mutations** : `onReceive(FileGridMutationCenter.mutations)` (filtré par drive), `onReceive(MediaMetadataStore.$revision)`, `onChange(itemsRevision)` ferme les présentations dont le fichier a disparu.
- **Présentations centralisées** : `detailRequest`, `tagsRequest`, `colorRequest`, `deleteRequest`, `renameRequest` via `FilePresentation`/`Intent` (`details`, `colorPicker`, `tags`, `rename`, `deleteConfirm`). `currentFile(matching:)` donne la version la plus récente.
- **États vides** : `EmptyStateView` selon source (Dossier vide / Aucun favori / Aucun upload récent / Aucun fichier avec ce tag / Corbeille vide / Aucun résultat). `filteredEmptyState` avec analyse vidéo / pages suivantes / Réessayer.
- **Scroll** : `scrollToTopRequest` → `proxy.scrollTo("file-grid-top")` ; `ScrollRevealMetrics` pour révéler/masquer la recherche ; padding bas 110.

### 10.2 `FileGridViewModel` (`@MainActor @Observable`)
- État : `items` (didSet → `itemsRevision`, `storeListSnapshot`), `isInitialLoading`, `isLoadingMore`, `hasMore`, `totalItemCount`, `errorMessage`, `mutationErrorMessage`, `categoriesById`, `isReloading`, `source`, `driveId`.
- `loadIfNeeded()` : snapshot mémoire puis disque, restaure `orderBy/order/cursor/hasMore/totalItemCount/fetchedAt`, puis `items` **en dernier** ; revalidation si disque ou > 60 s.
- `reload(sortedBy:forceNetwork:)` : génération `dataGeneration`, `fetchDirectoryCount` en parallèle, `filterItemsIfNeeded` (recents exclut les dossiers).
- `loadMoreIfNeeded` : dédup par `Set(ids)`, `forceNetwork` non requis.
- **Mutations optimistes** : `toggleFavorite` (retrait de la liste si source `.favorites`), `updateCategories`/`apply(.category)` (retrait si source `.category` correspondante), `trash`, `rename`, `setColor` (rollback conditionnel), `move`, `permanentlyDelete`, `restore`, actions de masse `trash(ids:)`/`move(ids:)`/`restore(ids:)`/`permanentlyDelete(ids:)` (concurrence 4, `reportPartialFailure`, publish `.removal`).
- `mergeUploaded` : complète dates manquantes, insère en tête, `resortAfterMerge`, `DirectoryListStore.mergeRecentUploads` + publish `.uploaded`.
- `groups(calendar:by:title:)` pour regroupements par date.

### 10.3 `FileCardView`
- Carte carrée stricte (`aspectRatio(1, .fit)`) — toutes identiques quelle que soit l'orientation d'origine.
- Miniature (`scaledToFill`, coins `DS.cardRadius`), sinon icône teintée sur fond `tint.opacity(0.10)`, sinon squelette.
- Overlays : badge favori (étoile dorée, masqué dans Favoris), badge sélection, badge play vidéo.
- Nom (footnote, 1 ligne, `.middle`), sous-titre (`showFileSizes ? taille : label`), pastilles de tags (max 4).
- Teinte dossier : `file.color` → `defaultFolderColor` → `kind.tint`.
- `.contextMenu` (hors sélection) : Détails, Changer la couleur (dossier), Télécharger (fichier), Tags, Favori, Renommer, Déplacer, Supprimer.
- `loadThumbnail` : cache mémoire → réseau → `thumbnailWhenAvailable`.
- `FolderColorPickerSheet` : palette 17 couleurs, sélection immédiate.

### 10.4 `FileGridMutationCenter`
- `PassthroughSubject<FileGridMutation>` ; cas `.favorite`, `.category`, `.removal`, `.uploaded` (propriété `driveId`). Diffuse les mutations confirmées sans rechargement.

### 10.5 Feuilles partagées
- `FileDetailSheet` : aperçu, Informations (Type/Taille/Emplacement/Ajouté/Modifié/Favori), Tags, Ouvrir/Télécharger ; renommer/supprimer ; pas d'actions si corbeille.
- `TagsEditorSheet` : grille de tags (colonnes `tagGridColumns`), coche si appliqué, toggle optimiste via `addCategory`/`removeCategory`, `onChanged`.
- `ApplyTagsSheet` : tags d'une **sélection** (états none/partial/all), applique retraits puis ajouts (`mapBounded` 4), erreurs partielles résumées.
- `MoveDestinationPicker` : navigation dans l'arborescence, exclut les dossiers sélectionnés, désactive le parent commun, `DriveFile.root(name:"Racine du drive")`.
- `FilterMenu` : popover 280 pt — Trier par, Ordre, Orientation vidéo, 4K+ (force media vidéos), Afficher (Tout/Vidéos/Images/Autres), Réinitialiser.
- `AddMenuButton` : Menu « Nouveau dossier / Importer photos-vidéos / Importer des fichiers » ; `PhotosPicker` 20 max encodage `.current` ; `DocumentPicker` UIKit.
- `DocumentPicker` : `UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)`, multisélection.

---

## 11. VISIONNEUSE

### 11.1 `ViewerRouter` (`@MainActor @Observable`)
- `MediaViewerContext { driveId, filters, searchText, viewModel?, files, startIndex, id }`.
- `open(_:siblings:filters:searchText:viewModel:)` : image/vidéo → `mediaContext` (filtre les médias des siblings, index du fichier) ; `.txt` → `textFile` ; autre non-dossier → `textFile` (fallback avec détection binaire).

### 11.2 `MediaPagerView`
- `TabView(.page, indexDisplayMode: .never)` sélectionné par **ID** (`selectedFileID`), `files` état local complété par pagination.
- Overlay images : favori + tag (gauche), titre copiable (centre, tap → « Copié » 1,5 s), fermer (droite).
- Geste vertical (min 12, `|Δy|>|Δx|`, seuil 130) → fermer (images non zoomées uniquement) ; suit le doigt à 55 %, opacity.
- Pagination continuée depuis le viewModel ; `loadMoreMediaIfNeeded` autour de l'index ; `refreshFiles` si `viewModel.items` change.
- `hiresPreloadIDs` = page courante + suivante. Une seule page active lit une vidéo.
- `scrollDisabled` suspendu quand un contrôle vidéo est touché (`controlInteractionFileIDs`).
- `ZoomablePhotoPage` : pinch `MagnifyGesture` (1→6, ancré), double-tap 1×↔2,5×, pan borné (`clampOffset`), GIF via `AnimatedGIFView` (`isPlaying: isActive && scenePhase == .active`), thumbnail instantané puis hires (retries `[.zero, 3, 8]` s), GIF retries `[.zero, 3, 8]` s.

### 11.3 `VideoPlayerView`
- Chrome **hors** de la zone vidéo : `topBar` (tag, favori, titre copiable, muet, fermer), `bottomBar` (play/pause, temps courant, `ScrubberBar`, durée, vitesse 0,5×→2×, AirPlay).
- Seule la page active charge/lit (`isActive`). `AVPlayer` : `automaticallyWaitsToMinimizeStalling = false`, `allowsExternalPlayback`, buffer 30 s. `PlayerLayerView` (`AVPlayerLayer`, `.resizeAspect`).
- Masquage auto contrôles 2,5 s ; bandes invisibles pour réafficher ; `controlRegionGesture` verrouille le pager.
- Double-tap ±10 s (détection manuelle <0,3 s / <44 pt, inversée en RTL) + pastille. Simple tap = toggle contrôles.
- Scrubbing : épaisseur 7→14, pouce 13→22 ; seeks live throttlés 0,1 s (tolérance 1,5 s) ; seek final tolérance 0,4 s. `displayedTime`.
- Observateurs : time observer 8 Hz, `AVPlayerItemDidPlayToEndTime`, route change (pause si vieux périphérique retiré), `timeControlStatus` (buffering). Watchdog anti-stall 20 s → relance max 2 fois (`VideoAssetCache.invalidate` + resume position). `retryPlaybackAfterProcessingDelay` si item `.failed`.
- `AudioSessionKeeper` : compteur de retain, `.playback`/`.moviePlayback`, libération différée 0,5 s. Pas de PiP.
- `ScrubberBar` : capsules fond/buffer/position blanche + pouce, geste min 0.

### 11.4 `TextFileViewer`
- Mode lecture (liens détectés cliquables → `SFSafariViewController`) / édition (crayon). Sauvegarde via `uploadContent` (nouvelle version), `MediaURLCache.invalidate`.
- Limite 5 Mo ; décodage BOM UTF-16 / UTF-8 / Windows-1252 / Latin-1 ; détection binaire (octet nul, >5 % de contrôle). Recherche (max 2000 résultats, surlignage orange/jaune, navigation). `PasteButton`. `interactiveDismissDisabled(hasUnsavedChanges)` + `confirmationDialog`.

### 11.5 `AnimatedGIFView`
- `UIViewRepresentable` → `GIFPlaybackView` : affiche première frame immédiatement, décode la suivante pendant l'affichage, délais respectés, boucle selon `loopCount`, `resumeAspect`. Mémoire constante.

---

## 12. DESIGN SYSTEM & UI

- **`DS`** : `cardRadius 18`, `tabBarRadius 28`, `gridSpacing 10`, `gridMargin 14`, `searchBarInset 52`.
- `SectionHeader` (subheadline semibold, trait `isHeader`), `EmptyStateView` (`ContentUnavailableView`, padding top 60).
- **`FloatingTabBar`** : `HStack(spacing:4)` de `AppTab.allCases`, padding h10/v8, fond `.ultraThinMaterial` en `RoundedRectangle(28, .continuous)`, bordure `.quaternary`, ombre `black 0.12` r14 y6, padding h `DS.gridMargin+8`. Ondes : sélection snappy 0,25 ; resélection → `onReselect` ; haptique `.selection` (si `hapticFeedbackEnabled`) ; icône `.bounce`.
- **`UploadProgressPill`** : capsule `ultraThinMaterial` (progression, pourcentage ou erreur/succès), chevron.
- **`UploadProgressSheet`** : résumé + liste des transferts (statuts, progression, erreurs), « Effacer », detents `.medium/.large`.
- `DownloadProgressBanner` (dans MainTabView) : progression + nom + « Annuler ».
- **`AppIcon`** : icône 1024 (set `AppIcon.appiconset`). Propositions dans `Design/AppIconProposals/`.

---

## 13. TESTS & CI

### 13.1 Tests (exécutables `@main`, `precondition`, pas XCTest)
- **`Tests/GIFImageChecks.swift`** : crée un GIF 2 frames (délais 0,1/0,3, loop 0) → `frameCount==2`, `loopCount==0`, délais, `aspectRatio==2`, 32×16, `frame(at:2)==nil`, fichier conservé. Régression 120 frames 640×320 : première **ET** dernière conservent 640 px (ancien décodeur tombait à ~323). Faux GIF + PNG → `nil`. Stub `MediaURLCache` local. Sortie `"GIF decoding checks passed"`.
- **`Tests/FavoritesDiskCacheChecks.swift`** : survie JSON fichiers+tags, pagination, `fetchedAt` non renouvelé à l'écriture locale, restauration par nouvelle instance, isolation compte/drive, expiration 8 j, corruption → nil, `clear()` total. Sortie `"Favorites disk cache checks passed"`.

Compilation CI : `swiftc Orvian/Core/Media/GIFImageStore.swift Tests/GIFImageChecks.swift -o ...`.

### 13.2 CI `.github/workflows/build.yml`
Sur `macos-26` :
1. Checkout (fetch-depth 0).
2. Calcul de la prochaine version sémantique depuis le dernier tag (push sur `main`).
3. Mise à jour `MARKETING_VERSION` dans `project.yml`.
4. `python3 .github/scripts/check_favorites_cache.py`.
5. Compilation + exécution du test GIF.
6. `brew install xcodegen` → `xcodegen generate`.
7. `xcodebuild ... CODE_SIGNING_ALLOWED=NO ... clean build`.
8. Packaging `Payload/Orvian.app` → `Orvian-<version>-unsigned.ipa` → artefact.
9. Sur push `main` : `update_repo.py` régénère `repo.json`, commit, tag `v<version>`, Release GitHub.

**Secrets CI** : injecter les éventuels secrets via GitHub Secrets, jamais en clair dans les fichiers.

### 13.3 `repo.json` (source LiveContainer/AltStore)
Champs : `name`, `identifier`, `tintColor`, `iconURL`, `apps[]` (`name`, `bundleIdentifier`, `version`, `downloadURL`, `iconURL`, `tintColor`, `category: utilities`, `size`).

---

## 14. SÉCURITÉ

- Token uniquement vers `api.infomaniak.com` et `*.upload.kdrive.infomaniak.com` (validation d'hôte + redirections filtrées).
- URLs média signées sans en-tête d'auth.
- Token dans le Keychain, repli UserDefaults pour LiveContainer. **Aucun secret commité** (`.env`/`.env.local` ignorés, cf. RÈGLE 3).
- Code de verrouillage stocké **haché** (SHA-256), biométrie `LocalAuthentication`.

---

## 15. CRITÈRES DE RECETTE / FONCTIONNALITÉS À VÉRIFIER

1. 5 onglets flottants translucides, seul Accueil persiste son état de scroll.
2. Navigation dossiers (dossiers en premier), breadcrumb, pagination infinie, pull-to-refresh, contenu conservé pendant rechargement.
3. Cartes strictement carrées uniformes, badges favori/vidéo/tags, teinte de dossiers.
4. Visionneuse unique images+vidéos : swipe ordre de l'onglet, pagination continuée, zoom/double-tap, fermeture verticale, GIF animés, seule la page active lit.
5. Vidéo : chrome complet, AirPlay, vitesse, scrubber, double-tap ±10 s, reprise anti-stall.
6. Texte : lecture/édition, liens, recherche, limite 5 Mo, détection binaire.
7. Favoris/tags optimistes depuis cartes et visionneuses, cohérence mutuelle via `FileGridMutationCenter`.
8. Upload photos/fichiers (v3, chunked ≥ 95 Mo, conflits renommés), pill + feuille + bannière.
9. Téléchargement + feuille de partage, nom sûr, refresh d'URL.
10. Création dossier, renommage, couleur, déplacement, corbeille/restauration/suppression définitive.
11. Réglages complets et persistants ; purge de cache ; verrouillage code/Face ID.
12. Onboarding token + découverte comptes/drives + changement de drive.
13. Cache miniatures mémoire/disque LRU 250 Mo, listings TTL 5 min, préchargement Wi-Fi.
14. Robuste en LiveContainer (Keychain avec repli, pas d'entitlement, IPA non signé).
15. Aucun secret publié ; `.env` créé localement et ignoré par Git ; API toujours vérifiée dans `Api infomaniak.json`.
