import AppKit
import Observation
import os

struct LicenseInfo: Codable, Equatable, Sendable {
    var key: String
    var instanceID: String
    var customerName: String?
    var customerEmail: String?
    var lastValidated: Date

    /// The key with only its last group showing, for display.
    var maskedKey: String {
        let groups = key.split(separator: "-")
        guard let last = groups.last, groups.count > 1 else { return String(repeating: "•", count: max(key.count - 4, 0)) + key.suffix(4) }
        return groups.dropLast().map { String(repeating: "•", count: $0.count) }.joined(separator: "-") + "-" + last
    }
}

enum LicenseState: Equatable, Sendable {
    case trial(endsAt: Date)
    case trialExpired
    case licensed(LicenseInfo)
    /// A licensed copy that hasn't been able to re-validate for longer than the offline grace period.
    case unverified(LicenseInfo, since: Date)
    /// The server said the key is no longer good (disabled, expired, refunded, deleted).
    case invalid(LicenseInfo, reason: String)

    var info: LicenseInfo? {
        switch self {
        case .licensed(let info), .unverified(let info, _), .invalid(let info, _): info
        case .trial, .trialExpired: nil
        }
    }
}

/// Owns the license state: trial, activation against Lemon Squeezy, daily re-validation, offline grace.
@MainActor
@Observable
final class LicenseManager {
    private(set) var state: LicenseState
    private(set) var isBusy = false

    @ObservationIgnored private let client = LemonSqueezyClient()
    @ObservationIgnored private let log = Logger(subsystem: AppIdentity.id, category: "license")
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var onChange: [(LicenseState) -> Void] = []

    private enum Account {
        static let license = "license"
        static let trialStart = "trialStart"
    }

    init() {
        if let info = Self.loadInfo() {
            state = .licensed(info)
            refreshLicensedState()
        } else {
            state = Self.trialState()
        }
    }

    /// Whether Ledge's features are available.
    var isActive: Bool {
        switch state {
        case .trial, .licensed: true
        case .trialExpired, .unverified, .invalid: false
        }
    }

    var trialDaysLeft: Int? {
        guard case .trial(let endsAt) = state else { return nil }
        return max(0, Int(ceil(endsAt.timeIntervalSinceNow / 86400)))
    }

    func addObserver(_ handler: @escaping (LicenseState) -> Void) {
        onChange.append(handler)
    }

    func start() {
        guard timer == nil else { return }
        Task { await revalidateIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                Task { await self.revalidateIfDue() }
                self.refreshTrialState()
            }
        }
    }

    // MARK: Activation

    func activate(key rawKey: String) async -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "Enter your license key." }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await client.activate(key: key, instanceName: Self.instanceName)
            guard response.activated == true, let instance = response.instance, let meta = response.meta else {
                return "Lemon Squeezy didn't activate that key."
            }
            if let message = Self.storeMismatch(meta) { return message }
            let info = LicenseInfo(
                key: key, instanceID: instance.id, customerName: meta.customerName, customerEmail: meta.customerEmail,
                lastValidated: Date())
            Self.saveInfo(info)
            setState(.licensed(info))
            log.info("Activated license (instance \(instance.id, privacy: .public))")
            return nil
        } catch {
            log.notice("Activation failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    func deactivate() async {
        guard let info = state.info else { return }
        isBusy = true
        defer { isBusy = false }
        // Best effort: the server's instance list is tidied up, but a failure here shouldn't trap the user.
        _ = try? await client.deactivate(key: info.key, instanceID: info.instanceID)
        Self.saveInfo(nil)
        setState(Self.trialState())
        log.info("Deactivated license")
    }

    // MARK: Validation

    func revalidateIfDue(force: Bool = false) async {
        guard let info = state.info else { return }
        guard force || Date().timeIntervalSince(info.lastValidated) >= LicenseConfig.revalidateInterval else { return }
        do {
            let response = try await client.validate(key: info.key, instanceID: info.instanceID)
            if response.valid == true, let meta = response.meta, Self.storeMismatch(meta) == nil {
                var updated = info
                updated.lastValidated = Date()
                updated.customerName = meta.customerName ?? info.customerName
                updated.customerEmail = meta.customerEmail ?? info.customerEmail
                Self.saveInfo(updated)
                setState(.licensed(updated))
            } else {
                let status = response.licenseKey?.status ?? "invalid"
                let reason = response.instance == nil && response.valid == false && status == "active"
                    ? "This Mac's activation was removed. Activate the key again."
                    : "This license is \(status)."
                log.notice("License no longer valid: \(reason, privacy: .public)")
                setState(.invalid(info, reason: reason))
            }
        } catch let failure as LemonSqueezyClient.Failure where failure.isDefinitive {
            setState(.invalid(info, reason: failure.localizedDescription))
        } catch {
            // Offline or the API is down: keep going until the grace period runs out.
            log.info("Validation deferred: \(error.localizedDescription, privacy: .public)")
            refreshLicensedState()
        }
    }

    private func refreshLicensedState() {
        guard let info = state.info, case .licensed = state else { return }
        if Date().timeIntervalSince(info.lastValidated) > LicenseConfig.offlineGrace {
            setState(.unverified(info, since: info.lastValidated))
        }
    }

    private func refreshTrialState() {
        if case .trial(let endsAt) = state, endsAt <= Date() {
            setState(.trialExpired)
        }
    }

    private func setState(_ new: LicenseState) {
        guard new != state else { return }
        state = new
        onChange.forEach { $0(new) }
    }

    // MARK: Storage

    private static var instanceName: String {
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return "\(host) (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))"
    }

    private static func storeMismatch(_ meta: LemonSqueezyClient.Meta) -> String? {
        if let store = LicenseConfig.storeID, store != meta.storeId {
            return "That key belongs to a different store."
        }
        if let product = LicenseConfig.productID, product != meta.productId {
            return "That key is for \(meta.productName ?? "a different product"), not Ledge."
        }
        return nil
    }

    private static func loadInfo() -> LicenseInfo? {
        guard let json = Keychain.string(for: Account.license), let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicenseInfo.self, from: data)
    }

    private static func saveInfo(_ info: LicenseInfo?) {
        guard let info else {
            Keychain.delete(Account.license)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(info) {
            Keychain.set(String(decoding: data, as: UTF8.self), for: Account.license)
        }
    }

    /// The trial starts the first time Ledge runs; the date lives in the Keychain so reinstalling doesn't reset it.
    private static func trialState() -> LicenseState {
        let formatter = ISO8601DateFormatter()
        let start: Date
        if let stored = Keychain.string(for: Account.trialStart), let date = formatter.date(from: stored) {
            start = date
        } else {
            start = Date()
            Keychain.set(formatter.string(from: start), for: Account.trialStart)
        }
        let endsAt = start + LicenseConfig.trialLength
        return endsAt > Date() ? .trial(endsAt: endsAt) : .trialExpired
    }
}
