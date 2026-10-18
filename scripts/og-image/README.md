# Social share image

`og.swift` renders the 1200×630 Open Graph card (`og.png` in the site repo) with SwiftUI, using the compiled app icon.

```bash
iconutil -c iconset "build/Build/Products/Debug/Sticky Windows.app/Contents/Resources/AppIcon.icns" -o /tmp/icon.iconset
swiftc -O -parse-as-library scripts/og-image/og.swift -o /tmp/og
/tmp/og /tmp/icon.iconset/icon_128x128@2x.png /tmp/og          # writes /tmp/og.png (1200×630) and /tmp/og@2x.png
sips -s format png -z 630 1200 /tmp/og@2x.png --out ../sticky-windows/og.png
```
