# App Quirks

Log of app-specific window behavior discovered while building Ledge.

## General
- There is no public API mapping a `CGWindowID` to an `AXUIElement`. The debug window list matches them by frame (±2 pt), so two windows of one app with identical frames can be paired in the wrong order.
- `kCGWindowName` (titles from the window server) needs Screen Recording permission; titles are read from AX instead.

## Parking (M2)
- macOS won't let a window go fully offscreen: it pulls a strip of it back on screen. M2's check (fail if ≥ 20 pt still visible) therefore failed for nearly every app, even Finder and Xcode, and fell back to minimize, which animates into the Dock. Fixed by parking at a bottom screen corner with a 1 pt sliver showing (the same trick other tiling window managers use) and accepting ≤ 4 pt of overlap as hidden. Corners whose window would spill onto another display are skipped.
- Hiding ladder: offscreen corner → hide the app (only when the parked window is its one visible standard window) → minimize. Offscreen failure is remembered per bundle ID (`hidingStrategies`, versioned so old bad entries are discarded). Failures are logged with target and landed frame: `log show --predicate 'subsystem == "vc.start.Ledge"' --info`.
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
