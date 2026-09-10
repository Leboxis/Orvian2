import Foundation
import Network

/// Surveille la connectivité pour autoriser ou non le préchargement en arrière-plan.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.orvian2.network-monitor")
    private let lock = NSLock()
    private var isOnWiFi = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.isOnWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    /// Le préchargement en arrière-plan n'est autorisé qu'en Wi-Fi confirmé.
    var allowsBackgroundPrefetch: Bool {
        lock.lock(); defer { lock.unlock() }
        return isOnWiFi
    }
}
