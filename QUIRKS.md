# App Quirks

Log of app-specific window behavior discovered while building Ledge.

## General
- There is no public API mapping a `CGWindowID` to an `AXUIElement`. The debug window list matches them by frame (±2 pt), so two windows of one app with identical frames can be paired in the wrong order.
- `kCGWindowName` (titles from the window server) needs Screen Recording permission; titles are read from AX instead.
