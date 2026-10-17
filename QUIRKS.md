# App Quirks

Log of app-specific window behavior discovered while building Ledge.

## General
- There is no public API mapping a `CGWindowID` to an `AXUIElement`. The debug window list matches them by frame (±2 pt), so two windows of one app with identical frames can be paired in the wrong order.
- `kCGWindowName` (titles from the window server) needs Screen Recording permission; titles are read from AX instead.

## Parking (M2)
- macOS won't let a window go fully offscreen. Measured (Chrome, Dock at bottom, 1800×1169 display): asked for top-left (−1348, 1168), it landed at y = 1054, leaving a 1 pt × 115 pt column visible plus the window shadow. macOS keeps ≥ 1 pt horizontally and keeps the title bar above the Dock's top (y = 1095). M2's check (fail if ≥ 20 pt visible) failed for nearly every app and fell back to minimize (Dock animation).
- Hiding ladder now: hide the app (⌘H) when the parked window is its only visible, unparked standard window: no strip, no Dock animation. Otherwise park at a bottom corner (≤ 4 pt overlap counts as hidden; corners spilling onto another display are skipped), accepting the thin strip. Minimize only if the app clamps even that. Offscreen failure is remembered per bundle ID (`hidingStrategies`, versioned so old bad entries are discarded). Failures are logged: `log show --predicate 'subsystem == "vc.start.Ledge"' --info`.
- App hiding is app-wide, so at most one parked window per app may be hidden that way. Bug found: two Finder windows both ended up app-hidden (a revealed parked window was wrongly treated as already tucked), and revealing one brought back both. Now a window only uses app-hide if every other standard window of the app is minimized, offscreen-parked, or not visible; and before unhiding an app for one window, its other app-hidden parked windows are moved to the corner first.
- Measured with Finder (trace logs): `NSRunningApplication.hide()` is asynchronous and took > 150 ms to land, so Ledge used to give up, park at a corner, and then have the hide land anyway. Ledge now polls up to 1 s.
- Measured with Finder: unhiding an app pulls its corner-parked windows back on screen (one jumped from 1799,1043 to 840,309). Simply activating the app does not. So app-hide is only used when the app has no other non-minimized parked window, and after any unhide (Ledge's or the user's ⌘-Tab/Dock) corner-parked windows of that app are re-tucked at +150 ms and +600 ms.
- If the user brings an app-hidden app back themselves (⌘-Tab, Dock), its parked window is treated as revealed.
- Offscreen-parked windows still belong to their app, so ⌘-Tab / Mission Control can focus them while they're invisible. Clicking the tab fixes it.
- If Ledge is killed (Xcode ■ Stop, crash) instead of quit, `applicationWillTerminate` doesn't run and offscreen windows stay stranded. Use Debug → Recover Off-Screen Windows. Proper persistence lands in M5.
- Full-screen windows are refused (beep).

## Drag to park (M3)
- Drags are detected with global mouse monitors: on mouse-down Ledge hit-tests the AX window under the cursor, then treats it as a window drag only once its origin moves and its size doesn't (text selection, sliders, and resizes are ignored).
- macOS 15 edge tiling ("Drag windows to left or right edge of screen to tile", `com.apple.WindowManager EnableTilingByEdgeDrag`, on by default) also reacts to left/right edge drags. On drop Ledge waits 350 ms for tiling to finish, then resizes the window back before hiding it, so you may see a brief tile flash. The status menu warns when it's on.
- Opt-in "Let Ledge Handle Left/Right Edge Drags" (menu + onboarding) writes `EnableTilingByEdgeDrag = false` while Ledge runs. The user's prior value (on/off/unset) is saved in Ledge's defaults and restored on quit, or on next launch after a crash/kill. If the user changes the setting themselves meanwhile, theirs is kept. WindowManager picks up the change immediately (confirmed on macOS 15+, Oct 2026); no restart needed.
- The restore frame for a dragged-in window is where it was when the drag began, not where it was dropped.
- Edges shared with another display aren't zones (the cursor passes through). Side zones stop below the menu bar.

## Reveal modes & lifecycle (M4)
- Peek tucks on: another app activating, focus moving to another window of the same app (AX `kAXFocusedWindowChangedNotification`), or the cursor staying outside window+tab (10 pt slack) for 0.5 s — but only after the cursor has been over the window once (or immediately for hover peeks). Focus-based tucks ignore the first 0.4 s after a reveal, since activating an app can briefly report focus on one of its other windows.
- Hover peeks activate the window's app (needed to bring it above other apps' windows) and hand focus back to the previous app on tuck.
- Dragging a revealed parked window more than 60 pt unparks it where it lands.
- "Close Window" reveals the window first so a save sheet isn't stranded offscreen; the tab stays until the window is actually destroyed.
- Tab removal: AX destroyed notification, app termination, plus a 3 s validity sweep as a safety net.

## Polish (M5)
- Slide animations step the window's AX position (~8 ms per frame, time-based so slow apps get fewer frames). Only corner-parked windows slide out; app-hidden and minimized windows appear via unhide/unminimize. Tuck slides to the edge first, then hides.
- App-hidden windows get their stored frame set *after* the app is hidden, so neither an edge slide nor macOS edge tiling's resize shows when it's unhidden.
- Persistence: `~/Library/Application Support/vc.start.Ledge/parked.json`, written about once a second when anything changed. Restore matches by bundle ID + exact window title; records wait up to 30 s after launch (or 20 s after any app launches) for the window to appear, then are dropped. Nothing is saved until the restore has loaded the file, so launching without Accessibility access doesn't wipe it.
- Revealing a window whose display was unplugged centers it on the main display instead.
- Full-screen detection: focused window of the frontmost app has `AXFullScreen`, checked on app activation, Space change, and once a second.
