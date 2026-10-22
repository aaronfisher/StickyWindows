import KeyboardShortcuts
import Sparkle
import SwiftUI

/// The settings panes, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, rules, permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .rules: "App Rules"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .shortcuts: "keyboard.fill"
        case .rules: "app.badge.checkmark.fill"
        case .permissions: "lock.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .blue
        case .shortcuts: .purple
        case .rules: .orange
        case .permissions: .green
        }
    }
}

/// System Settings–style window: panes in a sidebar on the left, the selected pane on the right.
struct SettingsView: View {
    let settings: SettingsStore
    let tilingOverride: TilingOverride
    let permission: AccessibilityPermission
    let launchAtLogin: LaunchAtLogin
    let updater: SPUUpdater
    let screenRecording: ScreenRecordingPermission

    @AppStorage("settingsPane") private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding<SettingsPane?>(get: { pane }, set: { if let new = $0 { pane = new } })) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(pane: pane)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(pane.title)
        }
        .frame(minWidth: 720, minHeight: 500)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general: GeneralSettings(settings: settings, tilingOverride: tilingOverride, launchAtLogin: launchAtLogin, updater: updater)
        case .appearance: AppearanceSettings(settings: settings)
        case .shortcuts: ShortcutSettings()
        case .rules: RulesSettings(settings: settings)
        case .permissions: PermissionSettings(permission: permission, screenRecording: screenRecording)
        }
    }
}

/// White symbol on a colored rounded square, like System Settings.
private struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    let tilingOverride: TilingOverride
    let launchAtLogin: LaunchAtLogin
    let updater: SPUUpdater
    @State private var automaticUpdates = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch Sticky Windows at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled))
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Check for updates automatically", isOn: $automaticUpdates)
                    .onChange(of: automaticUpdates) { updater.automaticallyChecksForUpdates = automaticUpdates }
                LabeledContent("Version") {
                    HStack {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                        Button("Check Now") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                    }
                }
            }
            .onAppear { automaticUpdates = updater.automaticallyChecksForUpdates }

            Section("Drag to park") {
                LabeledContent("Edges") {
                    HStack {
                        ForEach(Edge.allCases, id: \.self) { edge in
                            Toggle(edge.displayName, isOn: edgeBinding(edge)).toggleStyle(.checkbox)
                        }
                    }
                }
                LabeledContent("Dwell before drop") {
                    Slider(value: $settings.dwellTime, in: 0.1...1.0, step: 0.05) {
                        EmptyView()
                    } minimumValueLabel: { Text("Fast") } maximumValueLabel: { Text("Slow") }
                }
                Toggle(isOn: Binding(get: { tilingOverride.isEnabled }, set: tilingOverride.setEnabled)) {
                    Text("Let Sticky Windows handle left and right edge drags")
                    Text("Turns off macOS edge tiling while Sticky Windows runs; your setting comes back when Sticky Windows quits.")
                }
            }

            Section("Reveal") {
                Picker("Default mode", selection: $settings.defaultRevealMode) {
                    ForEach(RevealMode.allCases, id: \.self) { Text($0.displayName) }
                }
                Toggle("Hover over a tab to peek", isOn: $settings.hoverToPeek)
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0.1...1.5, step: 0.05)
                        Text(settings.hoverDelay, format: .number.precision(.fractionLength(2))).monospacedDigit()
                        Text("s")
                    }
                }
                .disabled(!settings.hoverToPeek)
                Toggle(isOn: $settings.animateWindows) {
                    Text("Slide windows in and out")
                    if settings.reduceMotion {
                        Text("Off while Reduce Motion is on in Accessibility settings.")
                    }
                }
            }

            Section("Spaces") {
                Toggle("Show tabs on all Spaces", isOn: $settings.tabsOnAllSpaces)
                Toggle("Hide tabs when a full-screen app is in front", isOn: $settings.hideTabsInFullScreen)
            }
        }
        .formStyle(.grouped)
    }

    private func edgeBinding(_ edge: Edge) -> Binding<Bool> {
        Binding(
            get: { settings.enabledEdges.contains(edge) },
            set: { enabled in
                if enabled { settings.enabledEdges.insert(edge) } else { settings.enabledEdges.remove(edge) }
            })
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Bindable var settings: SettingsStore
    private var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    var body: some View {
        Form {
            Section {
                Picker("Tab size", selection: $settings.tabSize) {
                    ForEach(TabSize.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show window titles", isOn: $settings.showTitles)
                Toggle("Show Dock badges on tabs", isOn: $settings.showBadges)
                Toggle(isOn: $settings.showThumbnails) {
                    Text("Show a window preview when hovering a tab")
                    Text(screenRecordingGranted
                        ? "Not shown while Hover to Peek is on."
                        : "Live previews need Screen Recording access (Permissions tab). Without it, the preview shows the icon and full title.")
                }
                Picker("Material", selection: $settings.tabMaterial) {
                    ForEach(TabMaterial.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $settings.tabOpacity, in: 0.3...1.0)
                        Text(settings.tabOpacity, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            Section("Accent color") {
                Toggle("Use a custom accent color", isOn: Binding(
                    get: { settings.customAccent != nil },
                    set: { settings.customAccent = $0 ? .blue : nil }))
                if settings.customAccent != nil {
                    ColorPicker("Color", selection: Binding(
                        get: { settings.customAccent ?? .accentColor },
                        set: { settings.customAccent = $0 }), supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Park frontmost window on left edge:", name: .parkFrontmostLeft)
                KeyboardShortcuts.Recorder("Park frontmost window on right edge:", name: .parkFrontmostRight)
                KeyboardShortcuts.Recorder("Park frontmost window on bottom edge:", name: .parkFrontmostBottom)
            } footer: {
                Text("Pressing a park shortcut on a window that's already parked and revealed tucks it away again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionSettings: View {
    let permission: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission

    var body: some View {
        Form {
            Section {
                row(
                    title: "Accessibility", detail: "Required to move, hide, and restore other apps' windows.",
                    granted: permission.isTrusted
                ) {
                    permission.requestAccess()
                    permission.openSystemSettings()
                }
                row(
                    title: "Screen Recording",
                    detail: screenRecording.needsRelaunch
                        ? "Granted. Relaunch Sticky Windows to turn live previews on."
                        : "Optional. Live previews of parked windows when you hover a tab; without it, previews show the app icon and title.",
                    granted: screenRecording.isGranted
                ) {
                    screenRecording.request()
                }
                if screenRecording.needsRelaunch {
                    Button("Relaunch Now") { screenRecording.relaunch() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permission.refresh()
            screenRecording.refresh()
            screenRecording.startPolling()
        }
    }

    private func row(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Button("Grant…", action: action)
            }
        }
    }
}
