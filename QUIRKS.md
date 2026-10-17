# App Quirks

Log of app-specific window behavior discovered while building Ledge.

## General
- There is no public API mapping a `CGWindowID` to an `AXUIElement`. The debug window list matches them by frame (±2 pt), so two windows of one app with identical frames can be paired in the wrong order.
- `kCGWindowName` (titles from the window server) needs Screen Recording permission; titles are read from AX instead.

## Parking (M2)
- Hiding tries an offscreen move first, re-reads the frame after 150 ms, and falls back to minimize if the app pulled the window back on screen. The fallback is remembered per bundle ID (`hidingStrategies` in UserDefaults; Debug → Reset Per-App Hiding Strategies clears it).
- Offscreen-parked windows still belong to their app, so ⌘-Tab / Mission Control can focus them while they're invisible. Clicking the tab fixes it.
- If Ledge is killed (Xcode ■ Stop, crash) instead of quit, `applicationWillTerminate` doesn't run and offscreen windows stay stranded. Use Debug → Recover Off-Screen Windows. Proper persistence lands in M5.
- Full-screen windows are refused (beep).

## Drag to park (M3)
- Drags are detected with global mouse monitors: on mouse-down Ledge hit-tests the AX window under the cursor, then treats it as a window drag only once its origin moves and its size doesn't (text selection, sliders, and resizes are ignored).
- macOS 15 edge tiling ("Drag windows to left or right edge of screen to tile", `com.apple.WindowManager EnableTilingByEdgeDrag`, on by default) also reacts to left/right edge drags. On drop Ledge waits 350 ms for tiling to finish, then resizes the window back before hiding it, so you may see a brief tile flash. The status menu warns when it's on.
- Opt-in "Let Ledge Handle Left/Right Edge Drags" (menu + onboarding) writes `EnableTilingByEdgeDrag = false` while Ledge runs. The user's prior value (on/off/unset) is saved in Ledge's defaults and restored on quit, or on next launch after a crash/kill. If the user changes the setting themselves meanwhile, theirs is kept. Unverified: whether WindowManager picks up the change live or only after it restarts.
- The restore frame for a dragged-in window is where it was when the drag began, not where it was dropped.
- Edges shared with another display aren't zones (the cursor passes through). Side zones stop below the menu bar.
