import SwiftUI

@main
struct Orvian2App: App {
    @State private var session = SessionStore()

    init() {
        let memory = 20 * 1024 * 1024
        let disk = 150 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memory, diskCapacity: disk, diskPath: "orvian2-shared")
        _ = NetworkMonitor.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .environment(session)
                .task {
                    await session.bootstrap()
                }
        }
    }
}
