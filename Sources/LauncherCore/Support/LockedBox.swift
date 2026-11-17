import Synchronization

/// A small thread-safe box for values shared with callbacks (e.g. `Process.terminationHandler`).
final class LockedBox<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) { storage = Mutex(value) }

    var value: Value {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
