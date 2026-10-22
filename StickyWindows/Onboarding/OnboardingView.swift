import SwiftUI

struct OnboardingView: View {
    let permission: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission
    let tilingOverride: TilingOverride
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Welcome to Sticky Windows")
                    .font(.title.bold())
                Text("Two permissions, then you're set. The first is required; the second makes it nicer.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                PermissionStep(
                    number: 1,
                    title: "Accessibility",
                    tag: ("Required", .orange),
                    detail: "Lets Sticky Windows move, hide, and restore other apps' windows. Nothing works without it.",
                    granted: permission.isTrusted,
                    buttonTitle: "Open System Settings",
                    footnote: "Turn on Sticky Windows under Privacy & Security → Accessibility. This updates automatically."
                ) {
                    permission.requestAccess()
                    permission.openSystemSettings()
                }

                PermissionStep(
                    number: 2,
                    title: "Screen Recording",
                    tag: ("Recommended", .blue),
                    detail: "Shows a live preview of a parked window when you hover its tab. Without it, previews show just the app icon and title. Nothing is recorded or sent anywhere.",
                    granted: screenRecording.isGranted,
                    buttonTitle: "Allow Screen Recording",
                    footnote: screenRecording.needsRelaunch
                        ? "Granted. macOS applies this on the next launch, so relaunch to turn previews on."
                        : "If no prompt appears, turn on Sticky Windows under Privacy & Security → Screen Recording.",
                    trailingAction: screenRecording.needsRelaunch ? ("Relaunch Now", { screenRecording.relaunch() }) : nil
                ) {
                    screenRecording.request()
                }
            }

            if permission.isTrusted {
                tilingChoice
            }

            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!permission.isTrusted)
        }
        .padding(28)
        .frame(width: 520)
        .onAppear {
            permission.startPolling()
            screenRecording.refresh()
            screenRecording.startPolling()
        }
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
}

/// One row of the checklist: number, title, status, explanation, and the button that grants it.
private struct PermissionStep: View {
    let number: Int
    let title: String
    let tag: (String, Color)
    let detail: String
    let granted: Bool
    let buttonTitle: String
    let footnote: String
    var trailingAction: (String, () -> Void)? = nil
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(granted ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 26, height: 26)
                if granted {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    Text(tag.0)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tag.1.opacity(0.15), in: Capsule())
                        .foregroundStyle(tag.1)
                    Spacer()
                    if granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack(spacing: 10) {
                        Button(buttonTitle, action: action)
                        Text(footnote).font(.caption).foregroundStyle(.tertiary)
                    }
                } else if let trailingAction {
                    HStack(spacing: 10) {
                        Button(trailingAction.0, action: trailingAction.1)
                        Text(footnote).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(granted ? 0.25 : 0.5), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.2), value: granted)
    }
}
