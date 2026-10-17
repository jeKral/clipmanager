import Foundation
import Combine
import ClipManagerCore

/// Owns the periodic relay communication: anonymous telemetry heartbeats
/// and remote license checks. Everything is best-effort — a missing or
/// unreachable relay never blocks the app (local state stands).
final class BackgroundSync: ObservableObject {

    /// Heartbeat / license-check interval (one hour).
    static let interval: TimeInterval = 3_600

    private let licenseStore: LicenseStore
    private var task: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(licenseStore: LicenseStore) {
        self.licenseStore = licenseStore
        // Re-check immediately when the relay URL changes.
        licenseStore.$config
            .map(\.relayURL)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.syncNow() }
            }
            .store(in: &cancellables)
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// One best-effort sync pass: heartbeat (if telemetry is on) + remote
    /// license check (if a license is stored). Only a DEFINITE relay answer
    /// (ok / expired / revoked) updates the local cache; `unknown` keeps
    /// the last known remote state.
    func syncNow() async {
        let store = licenseStore
        guard let baseURL = store.relayBaseURL else { return }
        let client = RelayClient(baseURL: baseURL)

        if store.telemetryEnabled {
            let heartbeat = Telemetry.currentHeartbeat(installId: store.installId)
            do {
                try await client.sendHeartbeat(heartbeat)
                Log.debug("heartbeat sent")
            } catch {
                Log.debug("heartbeat failed: \(error.localizedDescription)")
            }
        }

        if let license = store.license {
            do {
                let result = try await client.checkLicense(installId: store.installId, serial: license.serial)
                if result.status != .unknown {
                    store.applyRemote(result.status, note: result.note)
                    Log.debug("remote license status: \(result.status.rawValue)")
                }
            } catch {
                Log.debug("license check failed: \(error.localizedDescription)")
            }
        }
    }
}
