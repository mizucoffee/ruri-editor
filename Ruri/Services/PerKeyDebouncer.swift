//
//  PerKeyDebouncer.swift
//  ruri
//

import Foundation

@MainActor
final class PerKeyDebouncer<Key: Hashable & Sendable> {
    private let delayNanoseconds: UInt64
    private var tasksByKey: [Key: Task<Void, Never>] = [:]

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    // The explicit deinit keeps deallocation nonisolated. Without it the
    // compiler synthesizes an isolated deinit for this MainActor-isolated
    // class, and its runtime executor hop (swift_task_deinitOnExecutor)
    // crashes with a malloc abort when the debouncer is released from the
    // owning watcher's deinit.
    deinit {
        MainActor.assumeIsolated {
            cancelAll()
        }
    }

    // The slot is cleared before the action runs so the action may reschedule
    // the same key. A cancel that lands between the end of the sleep and the
    // MainActor hop does not suppress the pending action.
    func schedule(for key: Key, action: @escaping @MainActor () -> Void) {
        tasksByKey[key]?.cancel()
        tasksByKey[key] = Task { [weak self, delayNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            await MainActor.run {
                guard let self else { return }
                self.tasksByKey[key] = nil
                action()
            }
        }
    }

    func cancel(for key: Key) {
        tasksByKey.removeValue(forKey: key)?.cancel()
    }

    func cancelAll() {
        for key in Array(tasksByKey.keys) {
            cancel(for: key)
        }
    }
}
