import GameController
import Observation

/// Connected game controllers with battery level, for the toolbar.
@Observable
final class ControllerMonitor {
    struct Controller: Identifiable, Hashable {
        let id: ObjectIdentifier
        let name: String
        let battery: Float?

        var symbol: String {
            let lower = name.lowercased()
            if lower.contains("dualsense") || lower.contains("dualshock") || lower.contains("playstation") { return "playstation.logo" }
            if lower.contains("xbox") { return "xbox.logo" }
            return "gamecontroller.fill"
        }

        var batteryText: String? { battery.map { "\(Int(($0 * 100).rounded())) %" } }
    }

    private(set) var controllers: [Controller] = []
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var batteryTask: Task<Void, Never>?

    init() {
        update()
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        // Battery levels change slowly and have no notification; poll once a minute.
        batteryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.update()
            }
        }
    }

    private func update() {
        controllers = GCController.controllers().map { controller in
            Controller(
                id: ObjectIdentifier(controller),
                name: controller.vendorName ?? "Controller",
                battery: controller.battery.map(\.batteryLevel)
            )
        }
    }
}
