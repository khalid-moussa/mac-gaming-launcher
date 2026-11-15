import Foundation
import GameController
import Observation

public struct ConnectedController: Identifiable, Hashable, Sendable {
    public let id: String
    public let vendorName: String
    public let batteryLevel: Float?

    public var batteryText: String {
        guard let level = batteryLevel else { return "" }
        return "\(Int(level * 100))%"
    }

    public var iconName: String {
        let name = vendorName.lowercased()
        if name.contains("playstation") || name.contains("dualsense") || name.contains("dualshock") {
            return "playstation.logo"
        } else if name.contains("xbox") {
            return "xbox.logo"
        } else {
            return "gamecontroller.fill"
        }
    }
}

@Observable
@MainActor
public final class ControllerService {
    public static let shared = ControllerService()

    public var connectedControllers: [ConnectedController] = []

    public init() {
        updateControllers()
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateControllers()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateControllers()
            }
        }
    }

    public func updateControllers() {
        connectedControllers = GCController.controllers().map { gc in
            let battery = gc.battery?.batteryLevel
            return ConnectedController(
                id: "\(gc.hashValue)",
                vendorName: gc.vendorName ?? "Controller",
                batteryLevel: battery
            )
        }
    }
}
