import SwiftUI

/// Settings → License: trial status, activation, and deactivation.
struct LicenseSettings: View {
    let license: LicenseManager
    @State private var key = ""
    @State private var error: String?
    @State private var showDeactivateConfirm = false

    var body: some View {
        Form {
            Section {
                statusRow
            }

            switch license.state {
            case .licensed(let info), .unverified(let info, _), .invalid(let info, _):
                Section("Your license") {
                    LabeledContent("Key", value: info.maskedKey)
                    if let name = info.customerName { LabeledContent("Licensed to", value: name) }
                    if let email = info.customerEmail { LabeledContent("Email", value: email) }
                    LabeledContent("Last verified") {
                        Text(info.lastValidated, format: .relative(presentation: .named))
                    }
                    HStack {
                        Button("Verify Now") { Task { await license.revalidateIfDue(force: true) } }
                        Spacer()
                        Button("Deactivate This Mac…", role: .destructive) { showDeactivateConfirm = true }
                    }
                    .disabled(license.isBusy)
                }
                .confirmationDialog(
                    "Deactivate Ledge on this Mac?", isPresented: $showDeactivateConfirm, titleVisibility: .visible
                ) {
                    Button("Deactivate", role: .destructive) { Task { await license.deactivate() } }
                } message: {
                    Text("You can activate the same key again here or on another Mac at any time.")
                }
            case .trial, .trialExpired:
                Section {
                    TextField("License key", text: $key, prompt: Text("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit(activate)
                    HStack {
                        Button("Activate", action: activate)
                            .keyboardShortcut(.defaultAction)
                            .disabled(license.isBusy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                        if license.isBusy { ProgressView().controlSize(.small) }
                        Spacer()
                        Link(destination: LicenseConfig.checkoutURL) {
                            Label("Buy Ledge — $5", systemImage: "cart")
                        }
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                } header: {
                    Text("Activate")
                } footer: {
                    Text("Your key arrives by email after purchase. One purchase covers every Mac you own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch license.state {
        case .trial(let endsAt):
            let days = max(0, Int(ceil(endsAt.timeIntervalSinceNow / 86400)))
            row(symbol: "clock", tint: .orange, title: "Free trial: \(days) day\(days == 1 ? "" : "s") left",
                detail: "Ends \(endsAt.formatted(date: .abbreviated, time: .omitted)).")
        case .trialExpired:
            row(symbol: "exclamationmark.circle.fill", tint: .red, title: "Trial ended",
                detail: "Parking is paused until you activate a license.")
        case .licensed:
            row(symbol: "checkmark.seal.fill", tint: .green, title: "Licensed", detail: "Thanks for buying Ledge.")
        case .unverified(_, let since):
            row(symbol: "wifi.exclamationmark", tint: .orange, title: "License needs verifying",
                detail: "Ledge hasn't reached Lemon Squeezy since \(since.formatted(date: .abbreviated, time: .omitted)). Connect to the internet and click Verify Now.")
        case .invalid(_, let reason):
            row(symbol: "xmark.octagon.fill", tint: .red, title: "License not valid", detail: reason)
        }
    }

    private func row(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func activate() {
        error = nil
        Task {
            error = await license.activate(key: key)
            if error == nil { key = "" }
        }
    }
}
