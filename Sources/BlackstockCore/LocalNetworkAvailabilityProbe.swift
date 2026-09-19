#if os(macOS)
import Foundation
@preconcurrency import Network

public enum NetworkReachabilityState: String, Codable, Sendable {
    case available = "AVAILABLE"
    case unavailable = "UNAVAILABLE"
    case unknown = "UNKNOWN"
}

public struct LocalNetworkAvailabilityProbe: Sendable {
    public init() {}

    public func currentState() async -> NetworkReachabilityState {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(
                label: "de.blackstock.network-probe",
                qos: .utility
            )

            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                switch path.status {
                case .satisfied:
                    continuation.resume(returning: .available)
                case .unsatisfied, .requiresConnection:
                    continuation.resume(returning: .unavailable)
                @unknown default:
                    continuation.resume(returning: .unknown)
                }
            }
            monitor.start(queue: queue)
        }
    }
}
#endif
