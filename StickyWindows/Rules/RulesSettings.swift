import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → App Rules: one section per app.
struct RulesSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Text("Choose how Sticky Windows treats specific apps: keep them from being parked, park them automatically when they open, or—for apps like Mail that stay open without windows—open their main window when you click them in the Dock.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach($settings.appRules) { $rule in
                Section {
                    RuleEditor(rule: $rule)
                } header: {
                    RuleHeader(rule: rule) {
                        settings.appRules.removeAll { $0.bundleID == rule.bundleID }
                    }
                }
            }

            Section {
                AddAppMenu(settings: settings)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RuleHeader: View {
    let rule: AppRule
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: rule.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                .resizable()
                .frame(width: 20, height: 20)
            Text(rule.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Text("Remove")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .textCase(nil)
    }
}

private struct RuleEditor: View {
    @Binding var rule: AppRule
    /// The app's menu commands, read while it's running (needed to pick a specific command).
    @State private var commands: [AppMenu.Path] = []
    @State private var automatic: AppMenu.Path?
    @State private var isRunning = false

    var body: some View {
        Picker("Parking", selection: $rule.action) {
            ForEach(AppRule.Action.allCases, id: \.self) { Text($0.displayName) }
        }

        Toggle(isOn: $rule.dockClickShowsMainWindow) {
            Text("Dock click shows main window")
            Text("When you bring the app forward and only parked windows are open, Sticky Windows opens its main window. The app is never hidden as a whole, so its parked windows stay tucked.")
        }
        .onAppear(perform: loadCommands)
        .onChange(of: rule.dockClickShowsMainWindow) { loadCommands() }

        if rule.dockClickShowsMainWindow {
            Picker(selection: $rule.mainWindowCommand) {
                Text(automaticLabel).tag(AppMenu.Path?.none)
                if !commands.isEmpty {
                    Divider()
                }
                if let current = rule.mainWindowCommand, !commands.contains(current) {
                    Text(current.joined(separator: " → ")).tag(AppMenu.Path?.some(current))
                }
                ForEach(commands, id: \.self) { path in
                    Text(path.joined(separator: " → ")).tag(AppMenu.Path?.some(path))
                }
            } label: {
                Text("Menu command")
                if !isRunning {
                    Text("Open \(rule.name) to choose a specific command.")
                }
            }
        }
    }

    private var automaticLabel: String {
        automatic.map { "Automatic (\($0.joined(separator: " → ")))" } ?? "Automatic"
    }

    private func loadCommands() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleID).first else {
            isRunning = false
            return
        }
        isRunning = true
        commands = AppMenu.commands(pid: app.processIdentifier)
        automatic = AppMenu.automaticMainWindowCommand(pid: app.processIdentifier)
    }
}

private struct AddAppMenu: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Menu {
            let running = runningApps()
            if !running.isEmpty {
                Section("Running Apps") {
                    ForEach(running, id: \.bundleIdentifier) { app in
                        Button {
                            add(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!)
                        } label: {
                            Label {
                                Text(app.localizedName ?? app.bundleIdentifier!)
                            } icon: {
                                if let icon = app.icon { Image(nsImage: icon) }
                            }
                        }
                    }
                }
            }
            Button("Choose App…", action: chooseApp)
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func runningApps() -> [NSRunningApplication] {
        let taken = Set(settings.appRules.map(\.bundleID))
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !taken.contains($0.bundleIdentifier!) && $0.bundleIdentifier != own }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            add(bundleID: bundleID, name: name)
        }
    }

    private func add(bundleID: String, name: String) {
        guard !settings.appRules.contains(where: { $0.bundleID == bundleID }) else { return }
        settings.appRules.append(AppRule(bundleID: bundleID, name: name, action: .noParking))
    }
}
