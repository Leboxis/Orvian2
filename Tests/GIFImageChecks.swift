import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Vérifications du décodage GIF (exécutable `@main`, sans XCTest).
// Compilation CI :
//   swiftc Orvian2/Core/Media/GIFDecoder.swift Tests/GIFImageChecks.swift -o gifchecks

@main
struct GIFImageChecks {
    static func main() async {
        await checkBasicDecoding()
        await checkLargeGIF()
        checkInvalidInputs()
        print("GIF decoding checks passed")
    }

    // MARK: Helpers

    static func makeBitmap(width: Int, height: Int, color: (CGFloat, CGFloat, CGFloat)) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Crée un GIF animé sur disque et renvoie son URL + les délais.
    static func writeGIF(frames: Int, width: Int, height: Int, delays: [Double],
                         loopCount: Int, to url: URL) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        for index in 0..<frames {
            let intensity = CGFloat(index % 2 == 0 ? 0.2 : 0.8)
            let image = makeBitmap(width: width, height: height, color: (intensity, intensity, intensity))
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delays[index % delays.count]]
            ]
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination), "Impossible d'écrire le GIF")
    }

    static func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    // MARK: Checks

    static func checkBasicDecoding() async {
        let url = tempURL("basic-\(UUID().uuidString).gif")
        writeGIF(frames: 2, width: 32, height: 16, delays: [0.1, 0.3], loopCount: 0, to: url)

        guard let gif = GIFDecoder.decode(fromFile: url) else {
            preconditionFailure("Décodage GIF de base échoué")
        }
        precondition(gif.frameCount == 2, "frameCount attendu 2, obtenu \(gif.frameCount)")
        precondition(gif.loopCount == 0, "loopCount attendu 0, obtenu \(gif.loopCount)")
        precondition(abs(gif.aspectRatio - 2) < 0.01, "aspectRatio attendu 2, obtenu \(gif.aspectRatio)")

        let first = await gif.source?.frame(at: 0)
        let second = await gif.source?.frame(at: 1)
        precondition(first != nil && second != nil, "frames 0 et 1 attendues")
        precondition(abs((first?.delay ?? 0) - 0.1) < 0.005, "délai frame 0 attendu 0,1")
        precondition(abs((second?.delay ?? 0) - 0.3) < 0.005, "délai frame 1 attendu 0,3")

        let outOfRange = await gif.source?.frame(at: 2)
        precondition(outOfRange == nil, "frame(at: 2) doit être nil")

        precondition(FileManager.default.fileExists(atPath: url.path), "le fichier source doit être conservé")
    }

    /// Régression : un GIF 120 frames 640×320 doit conserver ses dimensions
    /// sur la première ET la dernière frame.
    static func checkLargeGIF() async {
        let url = tempURL("large-\(UUID().uuidString).gif")
        writeGIF(frames: 120, width: 640, height: 320, delays: [0.1], loopCount: 0, to: url)

        guard let gif = GIFDecoder.decode(fromFile: url) else {
            preconditionFailure("Décodage du grand GIF échoué")
        }
        precondition(gif.frameCount == 120, "frameCount attendu 120")
        let firstWidth = CGFloat(gif.firstFrame.width)
        precondition(abs(firstWidth - 640) < 1, "largeur première frame attendue 640, obtenue \(firstWidth)")

        let last = await gif.source?.frame(at: 119)
        let lastWidth = CGFloat(last?.image.width ?? 0)
        precondition(abs(lastWidth - 640) < 1, "largeur dernière frame attendue 640, obtenue \(lastWidth)")
    }

    static func checkInvalidInputs() {
        // Faux GIF : contenu texte avec extension .gif.
        let fake = tempURL("fake-\(UUID().uuidString).gif")
        try? Data("ceci n'est pas un gif".utf8).write(to: fake)
        precondition(GIFDecoder.decode(fromFile: fake) == nil, "un faux GIF doit renvoyer nil")

        // PNG valide : mauvais type UTI.
        let pngURL = tempURL("image-\(UUID().uuidString).png")
        let image = makeBitmap(width: 10, height: 10, color: (0.4, 0.6, 0.9))
        if let destination = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        precondition(GIFDecoder.decode(fromFile: pngURL) == nil, "un PNG doit renvoyer nil")
    }
}
