import SwiftUI

struct OnboardingView: View {
    let permission: AccessibilityPermission
    let tilingOverride: TilingOverride
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)

            Text("Welcome to Sticky Windows")
                .font(.title.bold())

            Text("Sticky Windows parks windows as tabs on the edges of your screen. To move, hide, and restore windows that belong to other apps, macOS requires you to grant Sticky Windows **Accessibility** access.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusRow

            if permission.isTrusted {
                tilingChoice
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

                    Text("Turn on Sticky Windows under Privacy & Security → Accessibility. This window updates automatically.")
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

    /// macOS edge tiling also grabs windows dragged to the left/right edges; offer to step it aside.
    private var tilingChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { tilingOverride.isEnabled }, set: { tilingOverride.setEnabled($0) })) {
                Text("Let Sticky Windows handle left and right edge drags").font(.callout.weight(.medium))
            }
            .toggleStyle(.switch)
            Text("macOS also tiles windows dragged to the left or right edge. Sticky Windows can turn that off while it runs and restore your setting when it quits. Keyboard and menu tiling keep working.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
