import SwiftUI

struct OnboardingView: View {
    let permission: AccessibilityPermission
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)

            Text("Welcome to Ledge")
                .font(.title.bold())

            Text("Ledge parks windows as tabs on the edges of your screen. To move, hide, and restore windows that belong to other apps, macOS requires you to grant Ledge **Accessibility** access.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusRow

            if permission.isTrusted {
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        permission.requestAccess()
                        permission.openSystemSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)

                    Text("Turn on Ledge under Privacy & Security → Accessibility. This window updates automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(32)
        .frame(width: 460)
        .onAppear { permission.startPolling() }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if permission.isTrusted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Accessibility access granted")
            } else {
                ProgressView().controlSize(.small)
                Text("Waiting for Accessibility access…")
            }
        }
        .font(.callout.weight(.medium))
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.quaternary, in: Capsule())
    }
}
