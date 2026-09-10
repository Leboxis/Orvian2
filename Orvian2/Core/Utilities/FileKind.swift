import SwiftUI

/// Type fonctionnel d'un fichier, avec icône et teinte associées.
enum FileKind: String, CaseIterable {
    case folder, image, video, audio, pdf, text
    case spreadsheet, presentation, archive, code, other

    init(extensionType: String?, mimeType: String?, fileName: String, isDirectory: Bool) {
        if isDirectory { self = .folder; return }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let functional = (extensionType ?? "").lowercased()
        let mime = (mimeType ?? "").lowercased()

        if ["image", "picture"].contains(functional) || mime.hasPrefix("image/") {
            self = .image; return
        }
        if ["video", "movie"].contains(functional) || mime.hasPrefix("video/") {
            self = .video; return
        }
        if ["audio", "sound", "music"].contains(functional) || mime.hasPrefix("audio/") {
            self = .audio; return
        }
        if functional == "pdf" || mime == "application/pdf" { self = .pdf; return }
        if ["text", "document", "word"].contains(functional) || mime.hasPrefix("text/") { self = .text; return }
        if ["spreadsheet", "excel"].contains(functional) { self = .spreadsheet; return }
        if ["presentation", "powerpoint"].contains(functional) { self = .presentation; return }
        if ["archive", "compressed"].contains(functional) { self = .archive; return }
        if ["code", "source"].contains(functional) { self = .code; return }

        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "bmp", "gif", "svg":
            self = .image
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            self = .video
        case "mp3", "m4a", "wav", "aac", "flac", "ogg":
            self = .audio
        case "pdf":
            self = .pdf
        case "txt", "md", "rtf", "doc", "docx", "pages":
            self = .text
        case "xls", "xlsx", "csv", "numbers":
            self = .spreadsheet
        case "ppt", "pptx", "key":
            self = .presentation
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            self = .archive
        case "swift", "js", "ts", "py", "rb", "go", "rs", "c", "cpp", "h", "java", "kt", "html", "css", "json", "xml", "sh", "yml", "yaml":
            self = .code
        default:
            self = .other
        }
    }

    var supportsThumbnail: Bool {
        switch self {
        case .image, .video, .pdf: return true
        default: return false
        }
    }

    var symbolName: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo.fill"
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext.fill"
        case .text: return "doc.text.fill"
        case .spreadsheet: return "tablecells.fill"
        case .presentation: return "rectangle.on.rectangle.fill"
        case .archive: return "archivebox.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc.fill"
        }
    }

    var label: String {
        switch self {
        case .folder: return "Dossier"
        case .image: return "Image"
        case .video: return "Vidéo"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        case .text: return "Texte"
        case .spreadsheet: return "Tableur"
        case .presentation: return "Présentation"
        case .archive: return "Archive"
        case .code: return "Code"
        case .other: return "Fichier"
        }
    }

    var tint: Color {
        switch self {
        case .folder: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .image: return Color(red: 0.20, green: 0.70, blue: 0.46)
        case .video: return Color(red: 0.91, green: 0.35, blue: 0.40)
        case .audio: return Color(red: 0.61, green: 0.35, blue: 0.90)
        case .pdf: return Color(red: 0.90, green: 0.26, blue: 0.26)
        case .text: return Color(red: 0.35, green: 0.44, blue: 0.55)
        case .spreadsheet: return Color(red: 0.13, green: 0.63, blue: 0.36)
        case .presentation: return Color(red: 0.95, green: 0.53, blue: 0.20)
        case .archive: return Color(red: 0.72, green: 0.55, blue: 0.28)
        case .code: return Color(red: 0.30, green: 0.55, blue: 0.85)
        case .other: return Color(red: 0.50, green: 0.53, blue: 0.58)
        }
    }
}
