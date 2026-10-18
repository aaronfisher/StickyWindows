# Sticky Windows — Edge Tabs for macOS

Name: **Sticky Windows** (working name was Ledge until October 2026). A modern revival of Mac OS 9 pop-up windows / Sticky Windows: drag any window to a screen edge and it collapses into a tab parked on that edge. Click the tab to bring the window back; click again (or click away) to tuck it away.

## Target
- macOS 15+ (Sequoia and later), Apple Silicon first (dev machine: M4 Mac).
- Swift 6, SwiftUI for UI, AppKit where needed (NSPanel, event monitors), Accessibility API (AXUIElement) for controlling other apps' windows.
- Menu-bar app (LSUIElement), no Dock icon.
- Distributed outside the Mac App Store as a notarized, Developer ID–signed .dmg with Sparkle auto-updates. (App Sandbox blocks the cross-app window control this needs.)

## Core behavior (v1)
1. **Park by drag.** While the user drags any window, if the cursor dwells in an edge zone (left, right, or bottom; ~8 px band, ~250 ms dwell), show a translucent drop indicator. On release, the window is parked:
   - Record the window's original frame, app, and AX reference.
   - Hide the window (move it offscreen or minimize; pick whichever is most reliable per app — see "Hiding strategy").
   - Create a tab on that edge at the release position.
2. **Tab appearance.** Small vertical tab (horizontal on bottom edge): app icon + truncated window title, rounded on the inward side, glassy material, follows light/dark mode. Tabs stack along an edge and never overlap; drag to reorder.
3. **Reveal.** Click a tab → the window slides out from that edge to its stored frame and gets focus. Two modes, settable per tab and globally:
   - **Pop-out:** stays open until the tab is clicked again or the window is dragged off.
   - **Peek:** auto-tucks back when the window loses focus or the cursor leaves it.
   - Optional: hover-to-peek with a configurable delay.
4. **Unpark.** Drag the tab away from the edge, or choose "Release" from the tab's context menu → window is restored to its original frame and the tab is removed.
5. **Context menu on tab:** Show/Hide, Release, Close Window, Switch mode (Pop-out/Peek), Move to other edge.
6. **Lifecycle.** If the underlying window closes or its app quits, remove the tab. Survive display changes (resolution, external monitor plugged/unplugged) by re-laying out tabs.

## Modern features (v1.x)
- Multi-display: tabs live on edges of any display; dropping between displays respected.
- Keyboard: global shortcut to park the frontmost window to a chosen edge; ⌥-number to toggle tab N; shortcut to show a quick switcher of all parked windows.
- Live thumbnail preview on hover (ScreenCaptureKit; only if the user grants Screen Recording — degrade gracefully to icon + title without it).
- Badges: show the app's Dock badge count on its tab when available.
- Tab groups: drop multiple windows onto the same tab to make a stacked group; clicking expands a mini list.
- Persistence: remember parked windows across app restarts where the window can be re-identified (app bundle ID + title match); otherwise drop the tab.
- Per-app rules: always park certain apps (e.g., Slack, Music) to a given edge on launch; exclude apps entirely.
- Spaces / full-screen: tabs appear on all Spaces by default (option: current Space only); hide tabs when a full-screen app is active.

## Settings (SwiftUI window)
- General: launch at login, edges enabled, dwell time, default reveal mode, hover-to-peek delay.
- Appearance: tab size, opacity, material, accent color, show titles yes/no.
- Shortcuts: all global hotkeys (use the KeyboardShortcuts package).
- Rules: per-app include/exclude/auto-park.
- Permissions: status + buttons for Accessibility (required) and Screen Recording (optional).

## Permissions & onboarding
- First run: short onboarding that explains why Accessibility access is needed, opens System Settings to the right pane, and polls `AXIsProcessTrusted()` until granted.
- App must stay fully functional (minus thumbnails) without Screen Recording.

## Architecture
- `WindowObserver` — global mouse event monitor + AXObserver notifications (window moved, resized, destroyed, app terminated) to detect drags and lifecycle.
- `WindowController` — wraps AXUIElement: read/write position & size, minimize, raise, focus. Handles per-app quirks.
- `ParkingManager` — source of truth for parked windows (edge, order, original frame, mode); persists to disk.
- `TabPanel` — borderless, non-activating NSPanel per tab (or one per edge), level above normal windows, `.canJoinAllSpaces`.
- `EdgeZoneDetector` — hit-testing for edge zones across all screens, accounting for menu bar, Dock, and notch.
- `SettingsStore` — @Observable settings backed by UserDefaults.

## Hiding strategy
Try in order, remembering what works per app bundle:
1. Move window just offscreen beyond the parked edge (fastest; enables slide-out animation).
2. Minimize via `kAXMinimizedAttribute` (fallback when apps clamp offscreen positions).
Known troublemakers to test early: Electron apps (Slack, VS Code, Discord), Chrome, Finder, Terminal, full-screen windows, windows with sheets open.

## Animation
- Slide in/out from the edge, ~200 ms, spring easing. Respect "Reduce motion".

## Milestones
1. **M1 — Skeleton:** menu-bar app, onboarding for Accessibility permission, list of all on-screen windows in a debug menu.
2. **M2 — Park & restore:** hotkey parks frontmost window to the right edge; tab appears; click restores. No drag yet.
3. **M3 — Drag to park:** edge-zone detection during drags, drop indicator, all three edges.
4. **M4 — Reveal modes & context menu:** Pop-out vs Peek, reorder, release, lifecycle cleanup.
5. **M5 — Polish:** settings window, multi-display, Spaces, animations, persistence.
6. **M6 — Extras:** thumbnails, badges, groups, per-app rules.
7. **M7 — Ship:** signing, notarization, Sparkle, .dmg build via GitHub Actions.

## Working rules for Claude Code
- Build locally on the Mac (needs Xcode and the real window server; this can't run in a Linux cloud agent).
- Commit to git after each working milestone step with a clear message; push to GitHub.
- Keep a `QUIRKS.md` logging any app-specific window behavior discovered.
- After each milestone, list what to manually test before moving on.
