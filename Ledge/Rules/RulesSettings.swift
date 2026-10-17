import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Rules: per-app exclude / auto-park.
struct RulesSettings: View {
    @Bindable var settings: SettingsStore
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose apps Ledge should never park or park automatically at launch, and apps like Mail whose main window should open when you click them in the Dock while only parked windows are open.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach($settings.appRules) { $rule in
                    RuleRow(rule: $rule)
                        .tag(rule.bundleID)
                }
            }
            .frame(minHeight: 220)
            .overlay {
                if settings.appRules.isEmpty {
                    Text("No rules yet").foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 0) {
                Menu {
                    let running = runningApps()
                    if !running.isEmpty {
                        Section("Running apps") {
                            ForEach(running, id: \.bundleIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app) }
                            }
                        }
                    }
                    Button("Choose App…", action: chooseApp)
                } label: {
                    Image(systemName: "plus")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                Button {
                    settings.appRules.removeAll { $0.bundleID == selection }
                    selection = nil
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
    }

    private func runningApps() -> [NSRunningApplication] {
        let taken = Set(settings.appRules.map(\.bundleID))
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !taken.contains($0.bundleIdentifier!) && $0.bundleIdentifier != own }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        addRule(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            addRule(bundleID: bundleID, name: name)
        }
    }

    private func addRule(bundleID: String, name: String) {
        guard !settings.appRules.contains(where: { $0.bundleID == bundleID }) else { return }
        settings.appRules.append(AppRule(bundleID: bundleID, name: name, action: .noParking))
        selection = bundleID
    }
}

private struct RuleRow: View {
    @Binding var rule: AppRule
    /// The app's menu commands, read when the row appears (only possible while the app is running).
    @State private var commands: [AppMenu.Path] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: rule.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(rule.name)
                Spacer()
                Picker("", selection: $rule.action) {
                    ForEach(AppRule.Action.allCases, id: \.self) { Text($0.displayName) }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 8) {
                Toggle("Dock click shows main window", isOn: $rule.dockClickShowsMainWindow)
                    .toggleStyle(.checkbox)
                    .help("When you bring this app forward and all it has open are parked windows, open its main window (for example Mail's viewer).")
                if rule.dockClickShowsMainWindow {
                    Picker("using", selection: $rule.mainWindowCommand) {
                        Text("Automatic").tag(AppMenu.Path?.none)
                        if let current = rule.mainWindowCommand, !commands.contains(current) {
                            Text(current.joined(separator: " → ")).tag(AppMenu.Path?.some(current))
                        }
                        ForEach(commands, id: \.self) { path in
                            Text(path.joined(separator: " → ")).tag(AppMenu.Path?.some(path))
                        }
                    }
                    .fixedSize()
                    .help(commands.isEmpty ? "Open the app to choose a specific menu command." : "The menu command that opens the main window.")
                }
            }
            .padding(.leading, 32)
            .font(.callout)
        }
        .padding(.vertical, 2)
        .onAppear(perform: loadCommands)
        .onChange(of: rule.dockClickShowsMainWindow) { loadCommands() }
    }

    private func loadCommands() {
        guard rule.dockClickShowsMainWindow,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleID).first else { return }
        commands = AppMenu.commands(pid: app.processIdentifier)
    }
}
