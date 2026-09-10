import AVKit
import Combine
import SwiftUI

/// Lecteur vidéo avec chrome complet (scrubber, vitesse, AirPlay, double-tap ±10 s).
struct VideoPlayerView: View {
    let driveId: Int
    let file: DriveFile
    let isActive: Bool
    let onClose: () -> Void
    let onInteractionChange: (Bool) -> Void

    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isBuffering = false
    @State private var controlsVisible = true
    @State private var rate: Float = 1
    @State private var timeObserver: Any?
    @State private var seekPill: String?
    @State private var lastTapTime: Date = .distantPast
    @State private var hideTask: Task<Void, Never>?
    @State private var stallAttempts = 0
    @State private var watchdog: Task<Void, Never>?
    @State private var cancellables = Set<AnyCancellable>()

    @AppStorage("hapticFeedbackEnabled") private var hapticsEnabled = true

    var body: some View {
        ZStack {
            PlayerLayerView(player: player)
                .ignoresSafeArea()
                .onTapGesture { handleTap() }
                .onAppear { player.isMuted = isMuted }

            if isBuffering {
                ProgressView().tint(.white)
            }

            if let seekPill {
                Text(seekPill)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Capsule())
            }

            if controlsVisible {
                controls
            }
        }
        .task(id: isActive) { await configure() }
        .onDisappear { teardown() }
    }

    private var controls: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "tag").foregroundStyle(.white)
            Spacer()
            Text(file.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button { isMuted.toggle(); player.isMuted = isMuted } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.white)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            ScrubberBar(progress: duration > 0 ? currentTime / duration : 0,
                        onScrub: { fraction in seek(to: fraction * duration, tolerance: 1.5) },
                        onEnd: { fraction in seek(to: fraction * duration, tolerance: 0.4) })
            HStack(spacing: 18) {
                Button { togglePlay() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).foregroundStyle(.white)
                }
                Text(Self.timeString(currentTime))
                    .font(.caption.monospacedDigit()).foregroundStyle(.white)
                Text("/").font(.caption).foregroundStyle(.white.opacity(0.6))
                Text(Self.timeString(duration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { cycleRate() } label: {
                    Text(rateLabel).font(.caption.bold()).foregroundStyle(.white).frame(minWidth: 34)
                }
                RoutePickerRepresentable().frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
    }

    private var rateLabel: String { rate == 1 ? "1×" : String(format: "%.1f×", rate) }

    // MARK: Configuration

    private func configure() async {
        onInteractionChange(true)
        defer { onInteractionChange(false) }
        guard isActive else {
            player.pause()
            return
        }
        NodeAudioSessionKeeper.shared.retain()
        guard let asset = await VideoAssetCache.shared.asset(driveId: driveId, fileId: file.id) else { return }
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = true

        duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        player.play()
        isPlaying = true
        player.rate = rate
        addObservers()
        scheduleHideControls()
        resetWatchdog()
    }

    private func addObservers() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.125, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                object: player.currentItem, queue: .main) { _ in
            isPlaying = false
            player.seek(to: .zero)
        }
        player.publisher(for: \.timeControlStatus).sink { status in
            isBuffering = status == .waitingToPlayAtSpecifiedRate
            isPlaying = status == .playing
        }.store(in: &cancellables)
        if let item = player.currentItem {
            item.publisher(for: \.isPlaybackBufferEmpty).sink { empty in
                isBuffering = empty
            }.store(in: &cancellables)
        }
    }

    private func teardown() {
        removeTimeObserver()
        watchdog?.cancel()
        cancellables.removeAll()
        NodeAudioSessionKeeper.shared.release()
        player.pause()
    }

    private func removeTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    // MARK: Interactions

    private func handleTap() {
        let now = Date()
        let isDoubleTap = now.timeIntervalSince(lastTapTime) < 0.3
        lastTapTime = now
        if isDoubleTap {
            seek(to: currentTime + 10, tolerance: 0.5)
            flashSeekPill("+10 s")
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
            if controlsVisible { scheduleHideControls() }
        }
    }

    private func flashSeekPill(_ text: String) {
        seekPill = text
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            seekPill = nil
        }
    }

    private func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        scheduleHideControls()
    }

    private func cycleRate() {
        let rates: [Float] = [0.5, 1, 1.5, 2]
        let index = rates.firstIndex(of: rate) ?? 1
        rate = rates[(index + 1) % rates.count]
        player.rate = rate
        scheduleHideControls()
    }

    private func seek(to seconds: Double, tolerance: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time,
                    toleranceBefore: CMTime(seconds: tolerance, preferredTimescale: 600),
                    toleranceAfter: CMTime(seconds: tolerance, preferredTimescale: 600))
        currentTime = clamped
        resetWatchdog()
    }

    private func scheduleHideControls() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
        }
    }

    private func resetWatchdog() {
        watchdog?.cancel()
        watchdog = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, isPlaying else { return }
            if stallAttempts < 2 {
                stallAttempts += 1
                let resume = currentTime
                VideoAssetCache.shared.invalidate(driveId: driveId, fileId: file.id)
                await configure()
                seek(to: resume, tolerance: 0.5)
            }
        }
    }

    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Couche AVPlayerLayer.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Barre de progression scrubbable.
struct ScrubberBar: View {
    let progress: Double
    let onScrub: (Double) -> Void
    let onEnd: (Double) -> Void

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    private var displayValue: Double { isScrubbing ? scrubValue : progress }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: isScrubbing ? 14 : 7)
                Capsule().fill(.white).frame(width: max(0, width * displayValue), height: isScrubbing ? 14 : 7)
                Circle()
                    .fill(.white)
                    .frame(width: isScrubbing ? 22 : 13)
                    .offset(x: max(0, width * displayValue) - (isScrubbing ? 11 : 6.5))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        scrubValue = min(max(value.location.x / width, 0), 1)
                        onScrub(scrubValue)
                    }
                    .onEnded { _ in
                        onEnd(scrubValue)
                        isScrubbing = false
                    }
            )
        }
        .frame(height: 24)
        .animation(.snappy(duration: 0.15), value: isScrubbing)
    }
}

/// Bouton AirPlay.
struct RoutePickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Conserve la session audio active pendant la lecture (compteur de retain).
final class NodeAudioSessionKeeper: @unchecked Sendable {
    static let shared = NodeAudioSessionKeeper()

    private let lock = NSLock()
    private var count = 0
    private var releaseTask: Task<Void, Never>?
    private init() {}

    func retain() {
        lock.lock()
        count += 1
        releaseTask?.cancel()
        lock.unlock()
        configureSession()
    }

    func release() {
        lock.lock()
        count = max(0, count - 1)
        let shouldRelease = count == 0
        lock.unlock()
        guard shouldRelease else { return }
        releaseTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }
}
