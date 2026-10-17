import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    let tilingOverride: TilingOverride
    let permission: AccessibilityPermission
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        TabView {
            GeneralSettings(settings: settings, tilingOverride: tilingOverride, launchAtLogin: launchAtLogin)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            RulesSettings(settings: settings)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            PermissionSettings(permission: permission)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    let tilingOverride: TilingOverride
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                Toggle("Launch Ledge at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled))
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

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
                    Text("Let Ledge handle left and right edge drags")
                    Text("Turns off macOS edge tiling while Ledge runs; your setting comes back when Ledge quits.")
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
                    Text(CGPreflightScreenCaptureAccess()
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
    @State private var screenRecording = CGPreflightScreenCaptureAccess()

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
                    title: "Screen Recording", detail: "Optional. Will enable live thumbnails on tabs; Ledge works fully without it.",
                    granted: screenRecording
                ) {
                    screenRecording = CGRequestScreenCaptureAccess()
                    if !screenRecording,
                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permission.refresh()
            screenRecording = CGPreflightScreenCaptureAccess()
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
