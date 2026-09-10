import CoreGraphics
import Foundation
import ImageIO

/// Décodage pur d'un GIF (testable sans dépendance réseau).
/// Types partagés par `GIFImageStore`.

/// Frame décodée.
struct GIFDecodedFrame: @unchecked Sendable {
    let image: CGImage
    let delay: Double
}

/// GIF décodé : première frame + source paresseuse des frames.
struct DecodedGIF: @unchecked Sendable {
    let firstFrame: CGImage
    let frameCount: Int
    let loopCount: Int
    let source: GIFFrameSource?
    let aspectRatio: CGFloat
}

/// Fournit les frames à la demande depuis un fichier local (mémoire constante).
actor GIFFrameSource {
    private let source: CGImageSource
    private let fileURL: URL
    private let delays: [Double]

    init(source: CGImageSource, fileURL: URL, delays: [Double]) {
        self.source = source
        self.fileURL = fileURL
        self.delays = delays
    }

    deinit { try? FileManager.default.removeItem(at: fileURL) }

    func frame(at index: Int) async -> GIFDecodedFrame? {
        await Task.detached(priority: .userInitiated) { [source, delays] in
            guard index >= 0, index < CGImageSourceGetCount(source),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            let delay = index < delays.count ? delays[index] : 0.1
            return GIFDecodedFrame(image: cgImage, delay: max(0.02, delay))
        }.value
    }
}

/// Décodage d'un GIF via ImageIO.
enum GIFDecoder {
    nonisolated static func decode(fromFile url: URL) -> DecodedGIF? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let type = CGImageSourceGetType(source) as String?
        guard type == "com.compuserve.gif" else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0, let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        var delays: [Double] = []
        for index in 0..<count {
            delays.append(delay(at: index, source: source))
        }
        var loopCount = 0
        if let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let loops = gif[kCGImagePropertyGIFLoopCount] as? Int {
            loopCount = loops
        }
        let aspectRatio = CGFloat(first.width) / CGFloat(max(1, first.height))
        let frameSource = GIFFrameSource(source: source, fileURL: url, delays: delays)
        return DecodedGIF(firstFrame: first, frameCount: count,
                          loopCount: loopCount, source: frameSource, aspectRatio: aspectRatio)
    }

    nonisolated static func delay(at index: Int, source: CGImageSource) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }
        if let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0 {
            return clamped
        }
        return 0.1
    }
}
