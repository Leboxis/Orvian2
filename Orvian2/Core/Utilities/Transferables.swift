import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Élément PhotoPicker importable, copié dans un dossier temporaire.
struct PickedPhotoTransferable: Transferable {
    let url: URL
    let fileName: String
    let fileExtension: String
    let totalBytes: Int64

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try Self.copy(received, defaultExtension: "jpg")
        }
        FileRepresentation(importedContentType: .movie) { received in
            try Self.copy(received, defaultExtension: "mov")
        }
    }

    private static func copy(_ received: ReceivedTransferredFile, defaultExtension: String) throws -> PickedPhotoTransferable {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Uploads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var originalName = received.file.lastPathComponent
        if originalName.isEmpty || originalName == "Unknown" {
            originalName = "Media.\(defaultExtension)"
        }
        let destination = directory.appendingPathComponent("\(UUID().uuidString)_\(originalName)")
        try? FileManager.default.removeItem(at: destination)
        if FileManager.default.fileExists(atPath: received.file.path) {
            try FileManager.default.copyItem(at: received.file, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int64 ?? 0
            return PickedPhotoTransferable(url: destination,
                                           fileName: originalName,
                                           fileExtension: (originalName as NSString).pathExtension,
                                           totalBytes: size)
        }
        return PickedPhotoTransferable(url: received.file, fileName: originalName,
                                       fileExtension: (originalName as NSString).pathExtension, totalBytes: 0)
    }
}

/// Sélecteur de documents UIKit (asCopy pour accéder au contenu).
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
