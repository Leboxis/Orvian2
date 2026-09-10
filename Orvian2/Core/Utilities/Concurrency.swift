import Foundation

/// Limiteur de concurrence (bornage des téléchargements/décodages).
final class AsyncThrottler: @unchecked Sendable {
    private let maxConcurrent: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        lock.lock()
        if active < maxConcurrent {
            active += 1
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            if active < maxConcurrent {
                active += 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func release() {
        lock.lock()
        if let waiter = waiters.first {
            waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        } else {
            active = max(0, active - 1)
            lock.unlock()
        }
    }
}

/// Exécute des opérations par lots bornés, en conservant l'ordre des résultats.
func mapBounded<Input, Output>(_ items: [Input],
                               concurrency: Int,
                               operation: (Input) async throws -> Output) async throws -> [Output] {
    guard !items.isEmpty else { return [] }
    let throttler = AsyncThrottler(maxConcurrent: concurrency)
    var results = [Output?](repeating: nil, count: items.count)
    try await withThrowingTaskGroup(of: (Int, Output).self) { group in
        for (index, item) in items.enumerated() {
            group.addTask {
                let output = try await throttler.withPermit { try await operation(item) }
                return (index, output)
            }
        }
        for try await (index, output) in group {
            results[index] = output
        }
    }
    return results.compactMap { $0 }
}

/// Filtre de progression monotone, appelable depuis n'importe quel thread.
final class ProgressGate: @unchecked Sendable {
    private var last = 0.0
    private let lock = NSLock()

    func shouldReport(_ value: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value >= last + 0.01 || value >= 1 else { return false }
        last = value
        return true
    }
}
