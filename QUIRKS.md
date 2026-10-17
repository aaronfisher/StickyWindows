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
