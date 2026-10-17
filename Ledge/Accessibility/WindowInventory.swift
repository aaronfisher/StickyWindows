import AppKit
import ApplicationServices

/// One on-screen window, merged from the window server list and the Accessibility tree.
@MainActor
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let icon: NSImage?
    let frame: CGRect
    /// The AX element for this window, when it could be matched (needs Accessibility access).
    let controller: WindowController?

    var title: String? {
        guard let title = controller?.title, !title.isEmpty else { return nil }
        return title
    }
}

@MainActor
enum WindowInventory {
    /// Normal-layer, on-screen windows of other apps, front to back.
    static func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let trusted = AXIsProcessTrusted()
        var axCache: [pid_t: [WindowController]] = [:]
        var claimed = Set<Int>()  // indices into axCache[pid] already matched, keyed by pid<<16|index

        return list.compactMap { entry -> WindowInfo? in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 1, bounds.height > 1 else { return nil }

            let app = NSRunningApplication(processIdentifier: pid)
            var controller: WindowController?
            if trusted {
                let candidates = axCache[pid] ?? WindowController.windows(forPID: pid)
                axCache[pid] = candidates
                // No public API maps CGWindowID → AXUIElement, so match by frame.
                if let index = candidates.indices.first(where: { i in
                    !claimed.contains(Int(pid) << 16 | i) && candidates[i].frame.map { $0.isClose(to: bounds) } == true
                }) {
                    claimed.insert(Int(pid) << 16 | index)
                    controller = candidates[index]
                }
            }

            return WindowInfo(
                id: number,
                pid: pid,
                appName: app?.localizedName ?? entry[kCGWindowOwnerName as String] as? String ?? "PID \(pid)",
                bundleID: app?.bundleIdentifier,
                icon: app?.icon,
                frame: bounds,
                controller: controller
            )
        }
    }
}

extension WindowInventory {
    /// Brings back unminimized windows left outside every display, e.g. after Ledge was killed while windows were parked.
    static func recoverOffscreenWindows(excluding isExcluded: (WindowController) -> Bool) -> Int {
        guard AXIsProcessTrusted(), let screen = NSScreen.main else { return 0 }
        let target = ScreenGeometry.axVisibleFrame(of: screen)
        var recovered = 0
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            for window in WindowController.windows(forPID: app.processIdentifier) {
                guard !window.isMinimized, !isExcluded(window),
                      let frame = window.frame, frame.width > 40, frame.height > 40,
                      !ScreenGeometry.isVisible(frame) else { continue }
                let origin = CGPoint(
                    x: target.minX + max(0, (target.width - frame.width) / 2),
                    y: target.minY + max(0, (target.height - frame.height) / 2))
                window.setPosition(origin)
                recovered += 1
            }
        }
        return recovered
    }
}

private extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
