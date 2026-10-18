# Sticky Windows

Edge tabs for macOS — a modern take on Mac OS 9's pop-up windows. (Called Ledge until October 2026; the GitHub repository keeps that name.) Drag any window to a screen edge and it tucks away into a tab parked on that edge. Click the tab to slide the window back out; click again to tuck it away.

Sticky Windows is a menu-bar app (no Dock icon) for macOS 15 Sequoia and later, written in Swift 6 with SwiftUI and AppKit, and it controls other apps' windows through the Accessibility API.

**Status:** Milestones 1–6 are done (see [SPEC.md](SPEC.md)). Next up: M7 (signing, notarization, Sparkle, .dmg via GitHub Actions).

## Using Sticky Windows

### Parking a window

- **Drag** a window by its title bar until the cursor rests against the left, right, or bottom edge. After a short dwell a drop indicator appears; let go to park it there.
- **Keyboard:** ⌃⌥⌘← / ⌃⌥⌘→ / ⌃⌥⌘↓ park the frontmost window on the left / right / bottom edge. Pressing it again on a revealed parked window tucks it back. Shortcuts can be changed in Settings.
- **Menu:** *Park Frontmost Window on Right Edge* in the menu-bar menu.

### Tabs

| Action | Result |
|---|---|
| Click | Reveal the window (it slides out), or tuck it away again |
| Hover | A preview of the window (live with Screen Recording access); or, with Hover to Peek on, the window itself |
| Drag along the edge | Reorder tabs |
| Drag ~80 pt away from the edge | Release: the window returns to where it was and the tab goes away |
| Right-click / Control-click | Show/Hide, Mode, Move to Edge, Release, Close Window |

Dragging a revealed window more than ~60 pt away also releases it, where you drop it.

Tabs show the app's **Dock badge** (unread counts and the like) when it has one.

### Tab groups

Drag a window onto an existing tab — it highlights with a **+** — to stack them into one group tab showing the apps' icons and a count. Click the group tab for a mini list: click a row to show or hide that window, or its ↩︎ button to release it. Right-click the group for Move to Edge, Ungroup, and Release All. Dragging the group tab reorders or releases the whole group.

### Reveal modes

- **Pop-out** (default): the window stays out until you click the tab again.
- **Peek:** the window tucks itself back when it loses focus or the cursor leaves it. Peek tabs show a small dot.

Set the default in Settings or the menu; override per tab from its context menu.

### Settings

Open with *Settings…* (⌘,) in the menu-bar menu. Panes are listed in a sidebar, like System Settings:

- **General:** launch at login, which edges accept drops, dwell time, default reveal mode, hover-to-peek and its delay, slide animations (off automatically with Reduce Motion), letting Sticky Windows handle left/right edge drags, tabs on all Spaces vs. the current one, hiding tabs when a full-screen app is in front.
- **Appearance:** tab size, window titles on/off, material, opacity, accent color, Dock badges, hover previews.
- **Shortcuts:** park shortcuts for each edge.
- **App Rules:** one section per app. *Parking:* park normally, never park (drags and shortcuts ignore it), or park on the left/right/bottom edge at launch. *Dock click shows main window:* for apps like Mail that stay open without windows — when you bring the app forward and only parked windows are open, Sticky Windows opens its main window through the app's own menu command (automatic, or picked from the app's menus). Mail gets this rule by default.
- **Permissions:** Accessibility (required) and Screen Recording (optional, for live previews).

### macOS edge tiling

macOS 15 also tiles windows dragged to the left or right edge, which fights with Sticky Windows. *Let Sticky Windows handle left and right edge drags* (Settings → General, the menu, or onboarding) turns macOS's "Drag windows to left or right edge of screen to tile" off while Sticky Windows runs and restores your setting when it quits — or on the next launch, if it crashed. Keyboard and menu tiling keep working.

### Across restarts

Parked windows are saved to `~/Library/Application Support/vc.theshirleycompany.StickyWindows/parked.json` and re-parked when Sticky Windows launches again, matched by app and exact window title. Quitting Sticky Windows (⌘Q) always puts every parked window back first.

## How windows are hidden

macOS never lets a window go fully off screen — it keeps at least a 1 pt column visible and the title bar above the Dock. So Sticky Windows picks, per window:

1. **Hide the app** (like ⌘H) when the parked window is its app's only visible window. Nothing stays on screen and nothing animates into the Dock.
2. **Park at a bottom screen corner** for apps with other windows still in use. A thin strip of the window (about 1 pt wide) stays visible there.
3. **Minimize** only if an app refuses both.

[QUIRKS.md](QUIRKS.md) logs the measurements and app-specific behavior behind this.

## Licensing

Sticky Windows is sold through [Lemon Squeezy](https://www.lemonsqueezy.com) ($5, unlimited devices) and uses its public [License API](https://docs.lemonsqueezy.com/api/license-api), so the app holds no API key.

- **Trial:** 14 days from first launch; the start date is kept in the Keychain so reinstalling doesn't reset it.
- **Activation:** Settings → License. The key is activated with one instance per Mac (named after the Mac) and stored in the Keychain with the instance ID.
- **Re-validation:** once a day. A key the server reports as disabled, expired, or deactivated stops working at once; being offline is fine for 30 days, after which Sticky Windows asks to verify.
- **When unlicensed** (trial over, or a bad key): parking stops, drags and shortcuts open the License pane, and parked windows are released.

Before shipping, fill in `StickyWindows/Licensing/LicenseConfig.swift` with the store ID, product ID, and checkout URL from the Lemon Squeezy dashboard, and set the product's license activation limit to unlimited.

## Website

The marketing site is a single static page in [docs/index.html](docs/index.html), with a working model of the parking gesture built in HTML. Serve it with GitHub Pages (Settings → Pages → Deploy from branch → `main`, folder `/docs`) or preview it locally:

```bash
python3 -m http.server 8765 --directory docs
```

## Building

Requirements: macOS 15+, Xcode with the macOS 15 SDK or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
```

```bash
open StickyWindows.xcodeproj
```

Then build and run the **StickyWindows** scheme (⌘R). The project is generated from [project.yml](project.yml) — edit that, not the `.xcodeproj`, and re-run `xcodegen generate` after adding or removing files. Swift packages: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

**App icon:** `StickyWindows/Resources/AppIcon.icon` is an Icon Composer file (open it with Icon Composer, which ships inside Xcode). Its layers are SVGs in `Assets/`; Xcode compiles it to the Liquid Glass icon plus `AppIcon.icns` for older macOS.

**Signing:** the project uses automatic signing with an Apple Development certificate for The Shirley Company LLC (team `F5N4RH3674`); Xcode creates the certificate on first build if needed. A stable signing identity is what lets macOS keep Sticky Windows' Accessibility permission across rebuilds — never switch to "Sign to Run Locally". To build under another team, change `DEVELOPMENT_TEAM` in `project.yml`. The app is intentionally not sandboxed: the App Sandbox blocks controlling other apps' windows.

On first launch Sticky Windows walks you through granting Accessibility access in System Settings → Privacy & Security → Accessibility.

## Development notes

- **Quit with ⌘Q from Sticky Windows' menu, not Xcode's Stop button.** Stop kills Sticky Windows without restoring parked windows. They're re-parked on the next launch; if a window is ever stranded, use *Debug → Recover Off-Screen Windows*.
- **Logs** use subsystem `vc.theshirleycompany.StickyWindows`. Hiding fallbacks are logged at notice level; frame timing and hide/reveal state traces at debug level:

  ```bash
  /usr/bin/log show --last 10m --predicate 'subsystem == "vc.theshirleycompany.StickyWindows"' --debug
  ```

  In zsh, `log` is a shell builtin — use the full `/usr/bin/log` path.
- **Debug menu** (in the menu-bar menu): list of on-screen windows (click to raise), copy the list, recover off-screen windows, reset per-app hiding strategies.

### Layout

| Folder | Contents |
|---|---|
| `StickyWindows/App` | App entry, `AppDelegate`, shortcut names |
| `StickyWindows/Accessibility` | AX window wrapper, window list, screen geometry, AX notifications, background window mover, permission |
| `StickyWindows/Parking` | `ParkingManager` (source of truth), drag observer, edge zones, peek monitor, hiding strategies, persistence, macOS tiling override, slide animator |
| `StickyWindows/Tabs` | Tab panels, tab and group tab views, layout/drag/context menus, group list, drop indicator |
| `StickyWindows/Settings` | `SettingsStore`, settings window, launch at login |
| `StickyWindows/Rules` | Per-app rules model and Rules settings tab |
| `StickyWindows/Extras` | Dock badge reader, ScreenCaptureKit thumbnails, preview panel |
| `StickyWindows/Onboarding` | First-run Accessibility onboarding |
| `StickyWindows/Debug` | Menu-bar status item and debug menu |
