import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above normal windows on every Space.
final class TabPanel: NSPanel {
    let hostingView: TabHostingView

    init(rootView: some View) {
        hostingView = TabHostingView(rootView: AnyView(rootView))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Handles tab input in AppKit (SwiftUI only draws), so clicks, drags, hover, and context menus
/// work reliably in a panel that never becomes key.
final class TabHostingView: NSHostingView<AnyView> {
    var onClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onDragBegan: (CGPoint) -> Void = { _ in }
    var onDragChanged: (CGPoint) -> Void = { _ in }
    var onDragEnded: (CGPoint) -> Void = { _ in }
    var menuProvider: () -> NSMenu? = { nil }

    private var mouseDownLocation: CGPoint?
    private var isDragging = false
    private var trackingArea: NSTrackingArea?
    private let dragThreshold: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            return showMenu(for: event)
        }
        mouseDownLocation = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let location = NSEvent.mouseLocation  // Screen coordinates: the panel moves under the cursor.
        if !isDragging, hypot(location.x - start.x, location.y - start.y) >= dragThreshold {
            isDragging = true
            onDragBegan(start)
        }
        if isDragging { onDragChanged(location) }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            isDragging = false
        }
        guard mouseDownLocation != nil else { return }
        if isDragging {
            onDragEnded(NSEvent.mouseLocation)
        } else {
            onClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(for: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    private func showMenu(for event: NSEvent) {
        guard let menu = menuProvider() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// Menu item that runs a closure, for menus built on the fly.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, state: NSControl.StateValue = .off, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.state = state
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}

/// Lets SwiftUI content in a non-activating panel be clicked on the first try.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
