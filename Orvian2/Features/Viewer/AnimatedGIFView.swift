import SwiftUI
import UIKit

/// Affiche un GIF animé (décodage paresseux, mémoire constante).
struct AnimatedGIFView: View {
    let driveId: Int
    let file: DriveFile
    let isActive: Bool

    @State private var gif: GIFImageStore.GIFImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let gif {
                GIFPlaybackView(gif: gif, isPlaying: isActive)
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                Color.black
            }
        }
        .task(id: file.id) { await load() }
        .onChange(of: isActive) { _, _ in }
    }

    private func load() async {
        isLoading = true
        let retries: [UInt64] = [0, 3, 8]
        for (attempt, delay) in retries.enumerated() {
            if attempt > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            if let result = await GIFImageStore.shared.gif(driveId: driveId, fileId: file.id) {
                gif = result
                isLoading = false
                return
            }
        }
        isLoading = false
    }
}

/// Vue UIKit qui affiche successivement les frames d'un GIF.
struct GIFPlaybackView: UIViewRepresentable {
    let gif: GIFImageStore.GIFImage
    let isPlaying: Bool

    func makeUIView(context: Context) -> GIFPlaybackUIView {
        let view = GIFPlaybackUIView()
        view.configure(with: gif)
        view.isPlaying = isPlaying
        return view
    }

    func updateUIView(_ uiView: GIFPlaybackUIView, context: Context) {
        uiView.isPlaying = isPlaying
    }
}

final class GIFPlaybackUIView: UIView {
    private var gif: GIFImageStore.GIFImage?
    private var currentFrame = 0
    private var imageView = UIImageView()
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var loopsCompleted = 0
    private var nextDelay: Double = 0.1

    var isPlaying: Bool = false {
        didSet {
            if isPlaying { start() } else { stop() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { displayLink?.invalidate() }

    func configure(with gif: GIFImageStore.GIFImage) {
        self.gif = gif
        imageView.image = UIImage(cgImage: gif.firstFrame)
        currentFrame = 0
        loopsCompleted = 0
    }

    private func start() {
        guard displayLink == nil, let gif else { return }
        if gif.frameCount <= 1 { imageView.image = UIImage(cgImage: gif.firstFrame); return }
        lastFrameTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let gif, gif.frameCount > 1 else { return }
        let now = CACurrentMediaTime()
        if now - lastFrameTime < nextDelay { return }
        let nextFrame = (currentFrame + 1) % gif.frameCount
        if nextFrame == 0 {
            loopsCompleted += 1
            if gif.loopCount > 0 && loopsCompleted >= gif.loopCount {
                stop()
                return
            }
        }
        lastFrameTime = now
        currentFrame = nextFrame
        Task {
            if let frame = await gif.source?.frame(at: currentFrame) {
                await MainActor.run {
                    imageView.image = UIImage(cgImage: frame.image)
                    nextDelay = max(0.02, frame.delay)
                }
            }
        }
    }
}
