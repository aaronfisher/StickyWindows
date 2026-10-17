import AppKit
import Observation
import os

/// Source of truth for parked windows; persisted so they can be re-parked after Ledge restarts.
@MainActor
@Observable
final class ParkingManager {
    private(set) var parked: [ParkedWindow] = []

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let strategies = HidingStrategyStore()
    @ObservationIgnored var onNeedsPermission: () -> Void = {}
    @ObservationIgnored private lazy var tabs = TabPresenter(manager: self)
    @ObservationIgnored private lazy var peek = PeekMonitor(manager: self)
    @ObservationIgnored private let axEvents = AXWindowEvents()
    @ObservationIgnored private var hoverTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let persistence = ParkingPersistence()
    @ObservationIgnored private var lastSavedRecords: [ParkedRecord]?
    /// Saved records not yet matched to a window (apps still launching at login, say).
    @ObservationIgnored private var pendingRestore: [ParkedRecord] = []
    @ObservationIgnored private var restoreDeadline = Date.distantPast
    @ObservationIgnored private var housekeepingTicks = 0
    @ObservationIgnored private var isTerminating = false
    @ObservationIgnored private var didRestore = false
    @ObservationIgnored private var activeSlides = 0
    @ObservationIgnored private var deferredWork: [() -> Void] = []
    @ObservationIgnored private let log = Logger(subsystem: "vc.start.Ledge", category: "parking")

    init(settings: SettingsStore) {
        self.settings = settings

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        NotificationCenter.default.addObserver(forName: .ledgeTabLayoutChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullScreenSuppression() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.appTerminated(pid: pid) } }
        }
        workspace.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.appUnhidden(pid: pid) } }
        }
        workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                self?.whenNotAnimating { [weak self] in
                    if let pid { self?.peek.appActivated(pid: pid) }
                    self?.updateFullScreenSuppression()
                }
            }
        }
        workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.whenNotAnimating { self?.updateFullScreenSuppression() } }
        }
        workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Its windows take a moment to appear; housekeeping keeps retrying while records are pending.
            MainActor.assumeIsolated { self?.restoreDeadline = max(self?.restoreDeadline ?? .distantPast, Date() + 20) }
        }

        axEvents.handler = { [weak self] event, element, pid in
            self?.handle(event, element: element, pid: pid)
        }
        peek.start()
    }

    // MARK: Parking

    func parkFrontmostWindow(to edge: Edge = .right) async {
        guard AXIsProcessTrusted() else { return onNeedsPermission() }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = WindowController.focusedWindow(forPID: app.processIdentifier),
              let frame = window.frame else {
            log.info("Park: no frontmost window")
            return NSSound.beep()
        }

        if let existing = parked.first(where: { $0.window.isSameWindow(as: window) }) {
            // Hotkey on an already parked, revealed window tucks it away again.
            if existing.isRevealed { await tuck(existing) }
            return
        }
        await park(window, edge: edge, screen: ScreenGeometry.screen(containing: frame))
    }

    /// Parks `window` on `edge` of `screen`.
    /// - Parameters:
    ///   - offset: Where along the edge the tab should sit (AX coordinates); defaults to the window's center.
    ///   - restoreFrame: Frame to reveal the window at; defaults to its current frame.
    ///   - settleDelay: Time to let macOS finish any edge-tiling it starts on mouse-up before hiding.
    func park(
        _ window: WindowController, edge: Edge, screen: NSScreen?,
        offset: CGFloat? = nil, restoreFrame: CGRect? = nil, mode: RevealMode? = nil,
        settleDelay: Duration = .zero
    ) async {
        guard let current = window.frame else { return NSSound.beep() }
        let app = NSRunningApplication(processIdentifier: window.pid)
        guard !window.isFullScreen else {
            log.info("Park: \(app?.bundleIdentifier ?? "?", privacy: .public) window is full screen")
            return NSSound.beep()
        }

        // Re-parking a revealed window (dragged to an edge again) replaces its old tab, keeping its mode.
        let previous = parked.first { $0.window.isSameWindow(as: window) }
        if let previous { forget(previous) }

        let parkedWindow = ParkedWindow(
            window: window, app: app, frame: restoreFrame ?? current, edge: edge, screen: screen, offset: offset)
        parkedWindow.mode = mode ?? previous?.mode
        parkedWindow.hiddenBy = .offscreen  // Tab shows as tucked right away; hide() sets the real method.
        parked.append(parkedWindow)
        axEvents.watch(window)
        tabs.sync()
        if settleDelay > .zero {
            try? await Task.sleep(for: settleDelay)
        }
        await hide(parkedWindow)
    }

    // MARK: Reveal & tuck

    func effectiveMode(of parkedWindow: ParkedWindow) -> RevealMode {
        parkedWindow.mode ?? settings.defaultRevealMode
    }

    /// Whether this revealed window should tuck itself away on focus loss / cursor leave.
    func autoTucks(_ parkedWindow: ParkedWindow) -> Bool {
        parkedWindow.session?.trigger == .hover || effectiveMode(of: parkedWindow) == .peek
    }

    func tabClicked(_ parkedWindow: ParkedWindow) async {
        guard parkedWindow.window.isValid else { return remove(parkedWindow) }
        guard parkedWindow.isRevealed else { return reveal(parkedWindow, trigger: .click) }
        if parkedWindow.session?.trigger == .hover {
            // Clicking a hover peek keeps it out, following the tab's mode from here.
            parkedWindow.session?.trigger = .click
            parkedWindow.session?.previousApp = nil
            return
        }
        await tuck(parkedWindow)
    }

    func reveal(_ parkedWindow: ParkedWindow, trigger: RevealSession.Trigger = .click) {
        guard parkedWindow.window.isValid else { return remove(parkedWindow) }
        guard !parkedWindow.isRevealed, !parkedWindow.isTransitioning else { return }
        cancelHover(parkedWindow)
        let frontmost = NSWorkspace.shared.frontmostApplication
        // Only corner-parked windows slide; unhiding an app or unminimizing has its own transition.
        let slides = settings.shouldAnimateWindows && parkedWindow.hiddenBy == .offscreen
        let method = parkedWindow.hiddenBy?.rawValue ?? "?"
        let clock = Date()
        bringBack(parkedWindow)
        let bringBackMs = Int(Date().timeIntervalSince(clock) * 1000)
        // Its display may have been unplugged since it was parked.
        let target = ScreenGeometry.fitted(parkedWindow.storedFrame)
        parkedWindow.storedFrame = target
        let window = parkedWindow.window

        if slides, let start = edgeOrigin(for: parkedWindow, frame: target) {
            let prep = Date()
            // Resizing makes the app re-lay out; skip it when the size already matches.
            if let size = window.frame?.size, abs(size.width - target.width) > 1 || abs(size.height - target.height) > 1 {
                window.setSize(target.size)
            }
            window.setPosition(start)
            // Activate the app only once it has arrived: activation keeps the app busy for tens of ms.
            window.raise(activating: false)
            log.notice("""
                [timing reveal] \(parkedWindow.appName, privacy: .public) from=\(method, privacy: .public) \
                bringBack=\(bringBackMs, privacy: .public)ms prep(size+pos+raise)=\(Int(Date().timeIntervalSince(prep) * 1000), privacy: .public)ms
                """)
            parkedWindow.isTransitioning = true
            Task {
                await slide(
                    window, from: start, to: target.origin, duration: 0.26, easing: .springOut,
                    on: ScreenGeometry.screen(withDisplayID: parkedWindow.displayID))
                window.setFrame(target)
                window.raise()
                parkedWindow.isTransitioning = false
            }
        } else {
            let prep = Date()
            window.setFrame(target)
            window.raise()
            log.notice("""
                [timing reveal] \(parkedWindow.appName, privacy: .public) from=\(method, privacy: .public) no-slide \
                bringBack=\(bringBackMs, privacy: .public)ms frame+raise=\(Int(Date().timeIntervalSince(prep) * 1000), privacy: .public)ms
                """)
        }
        parkedWindow.hiddenBy = nil
        parkedWindow.session = RevealSession(
            trigger: trigger,
            previousApp: frontmost?.processIdentifier == parkedWindow.window.pid ? nil : frontmost)
    }

    func tuck(_ parkedWindow: ParkedWindow) async {
        guard parkedWindow.isRevealed, !parkedWindow.isTransitioning else { return }
        guard parkedWindow.window.isValid else { return remove(parkedWindow) }
        parkedWindow.isTransitioning = true
        defer { parkedWindow.isTransitioning = false }
        let session = parkedWindow.session
        parkedWindow.session = nil

        // Keep whatever frame the user moved/resized it to while it was out.
        if let frame = parkedWindow.window.frame, ScreenGeometry.isVisible(frame) {
            parkedWindow.storedFrame = frame
        }
        if let title = parkedWindow.window.title, !title.isEmpty {
            parkedWindow.title = title
        }
        if settings.shouldAnimateWindows, let frame = parkedWindow.window.frame,
           let end = edgeOrigin(for: parkedWindow, frame: frame) {
            await slide(
                parkedWindow.window, from: frame.origin, to: end, duration: 0.18, easing: .accelerate,
                on: ScreenGeometry.screen(withDisplayID: parkedWindow.displayID))
        }
        let hideStart = Date()
        await hide(parkedWindow)
        log.notice("""
            [timing tuck] \(parkedWindow.appName, privacy: .public) hide=\(Int(Date().timeIntervalSince(hideStart) * 1000), privacy: .public)ms \
            → \(parkedWindow.hiddenBy?.rawValue ?? "?", privacy: .public)
            """)

        // A hover peek borrowed focus; hand it back.
        if session?.trigger == .hover, let previous = session?.previousApp,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == parkedWindow.window.pid {
            previous.activate()
        }
    }

    func tabHoverChanged(_ parkedWindow: ParkedWindow, isHovering: Bool) {
        parkedWindow.isHovered = isHovering
        guard isHovering else { return cancelHover(parkedWindow) }
        guard settings.hoverToPeek, !parkedWindow.isRevealed, !parkedWindow.isDragging else { return }
        hoverTasks[parkedWindow.id]?.cancel()
        let delay = settings.hoverDelay
        hoverTasks[parkedWindow.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, parkedWindow.isHovered, !parkedWindow.isDragging,
                  self.parked.contains(where: { $0 === parkedWindow }) else { return }
            self.reveal(parkedWindow, trigger: .hover)
        }
    }

    func cancelHover(_ parkedWindow: ParkedWindow) {
        hoverTasks[parkedWindow.id]?.cancel()
        hoverTasks[parkedWindow.id] = nil
    }

    // MARK: Tab actions

    func setMode(_ mode: RevealMode?, for parkedWindow: ParkedWindow) {
        parkedWindow.mode = mode
        if effectiveMode(of: parkedWindow) == .popOut, parkedWindow.session?.trigger == .hover {
            parkedWindow.session?.trigger = .click
        }
    }

    func move(_ parkedWindow: ParkedWindow, to edge: Edge) async {
        guard edge != parkedWindow.edge else { return }
        parkedWindow.edge = edge
        let frame = parkedWindow.storedFrame
        parkedWindow.desiredOffset = edge.isVertical ? frame.midY : frame.midX
        tabs.layout()
        // An offscreen window has to move past the new edge.
        if parkedWindow.hiddenBy == .offscreen, !parkedWindow.isTransitioning {
            await hide(parkedWindow)
        }
    }

    func reorder(_ parkedWindow: ParkedWindow, to offset: CGFloat) {
        parkedWindow.desiredOffset = offset
    }

    /// Closes the underlying window. It's revealed first so a "Save changes?" sheet isn't left offscreen.
    func closeWindow(_ parkedWindow: ParkedWindow) {
        reveal(parkedWindow)
        guard parkedWindow.window.close() else { return NSSound.beep() }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !parkedWindow.window.isValid { remove(parkedWindow) }
        }
    }

    /// Restores a hidden window to its frame (a revealed one stays put) and removes the tab.
    func release(_ parkedWindow: ParkedWindow) {
        if parkedWindow.window.isValid, !parkedWindow.isRevealed {
            bringBack(parkedWindow)
            parkedWindow.window.setFrame(parkedWindow.storedFrame)
        }
        remove(parkedWindow)
    }

    /// Synchronous so it can run from `applicationWillTerminate`; never leave windows stranded offscreen.
    func releaseAll() {
        for parkedWindow in parked {
            release(parkedWindow)
        }
    }

    func isParked(_ window: WindowController) -> Bool {
        parked.contains { $0.window.isSameWindow(as: window) }
    }

    func tabFrame(of parkedWindow: ParkedWindow) -> CGRect? {
        tabs.frame(of: parkedWindow)
    }

    // MARK: Lifecycle

    /// A revealed parked window dragged well away from where it was revealed is unparked where it lands.
    func windowWasDragged(_ window: WindowController, from start: CGRect) {
        guard let parkedWindow = parked.first(where: { $0.window.isSameWindow(as: window) }),
              parkedWindow.isRevealed, !parkedWindow.isTransitioning,
              let end = window.frame, hypot(end.minX - start.minX, end.minY - start.minY) > 60 else { return }
        log.info("Unparked \(parkedWindow.appName, privacy: .public) by dragging the window off")
        remove(parkedWindow)
    }

    /// Safety net for windows that vanished without a destroyed notification.
    func removeInvalidWindows() {
        for parkedWindow in parked where !parkedWindow.isTransitioning && !parkedWindow.window.isValid {
            remove(parkedWindow)
        }
    }

    private func handle(_ event: AXWindowEvents.Event, element: AXUIElement, pid: pid_t) {
        switch event {
        case .destroyed:
            if let parkedWindow = parked.first(where: { CFEqual($0.window.element, element) }) {
                remove(parkedWindow)
            }
        case .titleChanged:
            if let parkedWindow = parked.first(where: { CFEqual($0.window.element, element) }),
               let title = parkedWindow.window.title, !title.isEmpty {
                parkedWindow.title = title
            }
        case .focusedWindowChanged:
            whenNotAnimating { [weak self] in self?.peek.focusedWindowChanged(pid: pid) }
        }
    }

    private func appTerminated(pid: pid_t) {
        let gone = parked.filter { $0.window.pid == pid }
        guard !gone.isEmpty else { return }
        for parkedWindow in gone { cancelHover(parkedWindow) }
        parked.removeAll { $0.window.pid == pid }
        axEvents.forget(pid: pid)
        tabs.sync()
    }

    private func remove(_ parkedWindow: ParkedWindow) {
        forget(parkedWindow)
        tabs.sync()
    }

    /// Drops the record without touching the window or tabs.
    private func forget(_ parkedWindow: ParkedWindow) {
        cancelHover(parkedWindow)
        axEvents.unwatch(parkedWindow.window)
        parked.removeAll { $0 === parkedWindow }
    }

    // MARK: Hiding

    /// Tries, in order: hiding the app, an offscreen corner, minimizing.
    ///
    /// macOS always keeps part of a window on screen (a 1 pt column, and the title bar above the Dock), so the
    /// corner leaves a visible strip. Hiding the app leaves nothing, so it's preferred whenever it hides nothing
    /// else. Offscreen failure is remembered per app.
    private func hide(_ parkedWindow: ParkedWindow) async {
        let window = parkedWindow.window
        let app = NSRunningApplication(processIdentifier: window.pid)
        if parkedWindow.hiddenBy == .minimize, window.isMinimized { return }
        if parkedWindow.hiddenBy == .appHidden, app?.isHidden == true { return }

        trace("hide begin canHideApp=\(canHideApp(for: parkedWindow))", parkedWindow)
        if let app, canHideApp(for: parkedWindow) {
            if app.hide() {
                // Hiding is asynchronous; Finder takes a few hundred ms. Giving up early would park the window at a
                // corner and then have the hide land anyway.
                for _ in 0..<20 where !app.isHidden {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                if app.isHidden {
                    // Put it back at its stored frame while it's out of sight (it may have slid to the edge, or
                    // been resized by macOS edge tiling), so unhiding shows it in the right place.
                    window.setFrame(parkedWindow.storedFrame)
                    parkedWindow.hiddenBy = .appHidden
                    traceApp("hide → appHidden", pid: window.pid)
                    return
                }
            }
            log.notice("\(parkedWindow.bundleID ?? "?", privacy: .public) refused to hide; trying offscreen")
        }

        if strategies.method(for: parkedWindow.bundleID) == .offscreen,
           let target = offscreenOrigin(for: parkedWindow) {
            window.setSize(parkedWindow.storedFrame.size)
            window.setPosition(target)
            // Some apps re-clamp asynchronously, so check after they've had a moment.
            try? await Task.sleep(for: .milliseconds(150))
            let landed = window.frame
            if let landed, ScreenGeometry.isEssentiallyOffscreen(landed) {
                parkedWindow.hiddenBy = .offscreen
                traceApp("hide → corner", pid: window.pid)
                return
            }
            log.notice("""
                \(parkedWindow.bundleID ?? "?", privacy: .public) clamped offscreen move to \
                \(target.debugDescription, privacy: .public); landed at \
                \(landed?.debugDescription ?? "?", privacy: .public)
                """)
            strategies.setMethod(.minimize, for: parkedWindow.bundleID)
            window.setFrame(parkedWindow.storedFrame)
        }

        window.setMinimized(true)
        parkedWindow.hiddenBy = .minimize
        traceApp("hide → minimize", pid: window.pid)
    }

    /// Hiding the app is only safe when it hides nothing the user didn't park.
    /// Hiding is app-wide, so every other window would come back with the app when it's revealed.
    /// Only minimized windows are unaffected by that.
    private func canHideApp(for parkedWindow: ParkedWindow) -> Bool {
        let blockers = WindowController.windows(forPID: parkedWindow.window.pid).filter { other in
            guard !other.isSameWindow(as: parkedWindow.window), !other.isMinimized,
                  other.subrole == kAXStandardWindowSubrole else { return false }
            // Any other parked window blocks it: a revealed one is on screen, and one parked at a corner gets
            // pulled back on screen when the app is later unhidden.
            if isParked(other) { return true }
            return other.frame.map { ScreenGeometry.isVisible($0) } == true
        }
        return blockers.isEmpty
    }

    /// Makes a hidden parked window showable (the caller then sets its frame), keeping the app's other
    /// parked windows tucked even though unhiding the app brings them all back on screen.
    private func bringBack(_ parkedWindow: ParkedWindow) {
        let pid = parkedWindow.window.pid
        let app = NSRunningApplication(processIdentifier: pid)
        traceApp("bringBack begin for #\(parkedWindow.id.uuidString.prefix(4))", pid: pid)
        let unhiding = app?.isHidden == true
        if unhiding {
            // Shouldn't normally exist alongside this one, but if so it now has to live at a corner.
            for other in parked where other !== parkedWindow && other.window.pid == pid && other.hiddenBy == .appHidden {
                other.hiddenBy = .offscreen
            }
        }
        unhide(parkedWindow)
        if app?.isHidden == true {
            // This window was at a corner while another parked window had the app hidden.
            app?.unhide()
        }
        if unhiding {
            retuckCorners(pid: pid, except: parkedWindow)
        }
    }

    /// Unhiding an app pulls its corner-parked windows back on screen (measured with Finder), so put them back.
    private func retuckCorners(pid: pid_t?, except: ParkedWindow?) {
        for delay in [150, 600] {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self else { return }
                for other in self.parked where other !== except && (pid == nil || other.window.pid == pid)
                    && other.hiddenBy == .offscreen && !other.isTransitioning {
                    guard let frame = other.window.frame, !ScreenGeometry.isEssentiallyOffscreen(frame),
                          let target = self.offscreenOrigin(for: other) else { continue }
                    other.window.setSize(other.storedFrame.size)
                    other.window.setPosition(target)
                    self.trace("retuck +\(delay)ms", other)
                }
            }
        }
    }

    /// Undoes whichever hiding method is in effect, without moving the window.
    private func unhide(_ parkedWindow: ParkedWindow) {
        switch parkedWindow.hiddenBy {
        case .minimize: parkedWindow.window.setMinimized(false)
        case .appHidden: NSRunningApplication(processIdentifier: parkedWindow.window.pid)?.unhide()
        case .offscreen, nil: break
        }
    }

    /// The user brought a hidden app back themselves (⌘-Tab, Dock): its parked window is out now.
    private func appUnhidden(pid: pid_t) {
        traceApp("app unhidden (notification)", pid: pid)
        retuckCorners(pid: pid, except: nil)
        for parkedWindow in parked where parkedWindow.window.pid == pid && parkedWindow.hiddenBy == .appHidden {
            parkedWindow.hiddenBy = nil
            parkedWindow.session = RevealSession(trigger: .click)
        }
    }

    /// macOS keeps part of every window on screen, so park at a bottom corner with as little showing as it allows.
    /// Corners whose window would spill onto another display are skipped.
    private func offscreenOrigin(for parkedWindow: ParkedWindow) -> CGPoint? {
        let size = parkedWindow.storedFrame.size
        let preferred = ScreenGeometry.screen(withDisplayID: parkedWindow.displayID)
        let screens = [preferred].compactMap { $0 } + NSScreen.screens.filter { $0 != preferred }

        for screen in screens {
            let frame = ScreenGeometry.axFrame(of: screen)
            let bottomRight = CGPoint(x: frame.maxX - 1, y: frame.maxY - 1)
            let bottomLeft = CGPoint(x: frame.minX - size.width + 1, y: frame.maxY - 1)
            let corners = parkedWindow.edge == .left ? [bottomLeft, bottomRight] : [bottomRight, bottomLeft]
            if let corner = corners.first(where: { ScreenGeometry.isEssentiallyOffscreen(CGRect(origin: $0, size: size)) }) {
                return corner
            }
        }
        return nil
    }

    // MARK: Animation

    private enum Easing: Equatable {
        /// Critically damped spring: starts at zero speed (no first-frame jump), settles without overshoot.
        case springOut
        /// Eases in, leaving fast: for windows tucking away.
        case accelerate

        func value(at t: Double) -> Double {
            switch self {
            case .springOut:
                // 1 - (1 + ωt)e^(-ωt), normalized so it lands exactly on 1.
                let omega = 9.0
                let raw = { (x: Double) in 1 - (1 + omega * x) * exp(-omega * x) }
                return raw(t) / raw(1)
            case .accelerate:
                return t * t
            }
        }
    }

    /// Moves a window once per display refresh. Moves are applied off the main thread, newest position wins.
    private func slide(
        _ window: WindowController, from: CGPoint, to: CGPoint, duration: TimeInterval, easing: Easing, on screen: NSScreen?
    ) async {
        let start = Date()
        let mover = AXWindowMover(element: window.element)
        var frames = 0
        var gapMax = 0.0
        var lastFrame = start
        let animator = WindowSlideAnimator(duration: duration) { t in
            let now = Date()
            gapMax = max(gapMax, now.timeIntervalSince(lastFrame))
            lastFrame = now
            let e = easing.value(at: t)
            mover.move(to: CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e))
            frames += 1
        }
        activeSlides += 1
        await animator.run(on: screen)
        await mover.flush()
        activeSlides -= 1
        if activeSlides == 0 { runDeferredWork() }

        // Frame timing, to diagnose stutter. frames = display refreshes; moves = positions the app applied.
        let total = Date().timeIntervalSince(start)
        let stats = mover.stats
        log.notice("""
            [timing slide] pid=\(window.pid, privacy: .public) \(easing == .springOut ? "out" : "in", privacy: .public) \
            planned=\(Int(duration * 1000), privacy: .public)ms actual=\(Int(total * 1000), privacy: .public)ms \
            frames=\(frames, privacy: .public) moves=\(stats.moves, privacy: .public) \
            ax avg=\(String(format: "%.1f", stats.axTotal / Double(max(stats.moves, 1)) * 1000), privacy: .public)ms \
            max=\(String(format: "%.1f", stats.axMax * 1000), privacy: .public)ms frameGapMax=\(String(format: "%.1f", gapMax * 1000), privacy: .public)ms
            """)
    }

    /// Runs `work` now, or once no slide is running: activation and focus handlers query the app over AX,
    /// which blocks the main thread while that app is busy.
    private func whenNotAnimating(_ work: @escaping () -> Void) {
        if isAnimating {
            deferredWork.append(work)
        } else {
            work()
        }
    }

    private func runDeferredWork() {
        let work = deferredWork
        deferredWork.removeAll()
        work.forEach { $0() }
    }

    /// While a window slides, polling and housekeeping wait so they can't steal a frame.
    var isAnimating: Bool { activeSlides > 0 }

    /// The window just past its parked edge, where slides start and end. macOS clamps it to a sliver anyway.
    private func edgeOrigin(for parkedWindow: ParkedWindow, frame: CGRect) -> CGPoint? {
        guard let screen = ScreenGeometry.screen(withDisplayID: parkedWindow.displayID) else { return nil }
        let bounds = ScreenGeometry.axFrame(of: screen)
        return switch parkedWindow.edge {
        case .right: CGPoint(x: bounds.maxX - 1, y: frame.minY)
        case .left: CGPoint(x: bounds.minX - frame.width + 1, y: frame.minY)
        case .bottom: CGPoint(x: frame.minX, y: bounds.maxY - 1)
        }
    }

    // MARK: Displays & Spaces

    private func screensChanged() {
        tabs.layout()
        // Corner positions depend on the display arrangement; a new display may now overlap one.
        retuckCorners(pid: nil, except: nil)
    }

    /// Hides all tabs while a full-screen window is in front, if the user wants that.
    func updateFullScreenSuppression() {
        guard settings.hideTabsInFullScreen, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = WindowController.focusedWindow(forPID: app.processIdentifier) else {
            return tabs.setSuppressed(false)
        }
        tabs.setSuppressed(window.isFullScreen)
    }

    // MARK: Persistence & housekeeping

    /// Called about once a second by `PeekMonitor`'s timer.
    func housekeeping() {
        guard !isAnimating else { return }
        housekeepingTicks += 1
        updateFullScreenSuppression()
        if housekeepingTicks % 3 == 0 { removeInvalidWindows() }
        restoreSavedIfNeeded()
        if !pendingRestore.isEmpty { attemptRestore() }
        saveIfChanged()
    }

    /// Loads windows parked in a previous run and re-parks the ones it can find (by app + exact title).
    /// Waits for Accessibility access; nothing is saved over the file until this has run.
    func restoreSavedIfNeeded() {
        guard !didRestore, AXIsProcessTrusted() else { return }
        didRestore = true
        pendingRestore = persistence.load()
        lastSavedRecords = pendingRestore
        // Apps launched at login may still be opening windows.
        restoreDeadline = Date() + 30
        attemptRestore()
    }

    /// Saves, then restores every window, without the restore being saved: next launch re-parks them.
    func prepareForTermination() {
        saveIfChanged()
        isTerminating = true
        releaseAll()
    }

    private func saveIfChanged() {
        // Before the restore has loaded the file, saving would wipe it.
        guard !isTerminating, didRestore else { return }
        let records = parked.compactMap(ParkedRecord.init) + pendingRestore
        guard records != lastSavedRecords else { return }
        persistence.save(records)
        lastSavedRecords = records
    }

    private func attemptRestore() {
        let stillWaiting = Date() < restoreDeadline
        var remaining: [ParkedRecord] = []
        for record in pendingRestore {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: record.bundleID).first else {
                if stillWaiting { remaining.append(record) }
                continue
            }
            let match = WindowController.windows(forPID: app.processIdentifier).first {
                $0.title == record.title && !isParked($0)
            }
            if let match {
                log.info("Restoring parked \(record.bundleID, privacy: .public) '\(record.title, privacy: .public)'")
                Task {
                    await park(
                        match, edge: record.edge, screen: ScreenGeometry.screen(withDisplayID: record.displayID),
                        offset: record.desiredOffset, restoreFrame: record.storedFrame, mode: record.mode)
                }
            } else if stillWaiting {
                remaining.append(record)
            } else {
                log.info("Dropping parked \(record.bundleID, privacy: .public) '\(record.title, privacy: .public)': no match")
            }
        }
        pendingRestore = remaining
    }

    // MARK: Tracing

    /// Detailed state dump for diagnosing hide/reveal across multi-window apps.
    /// Read with: log show --last 10m --predicate 'subsystem == "vc.start.Ledge"' --info
    private func trace(_ event: String, _ parkedWindow: ParkedWindow) {
        let app = NSRunningApplication(processIdentifier: parkedWindow.window.pid)
        let frame = parkedWindow.window.frame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "nil"
        log.notice("""
            [\(event, privacy: .public)] \(parkedWindow.appName, privacy: .public) \
            '\(parkedWindow.title, privacy: .public)' #\(parkedWindow.id.uuidString.prefix(4), privacy: .public) \
            hiddenBy=\(parkedWindow.hiddenBy?.rawValue ?? "revealed", privacy: .public) frame=\(frame, privacy: .public) \
            minimized=\(parkedWindow.window.isMinimized, privacy: .public) appHidden=\(app?.isHidden ?? false, privacy: .public)
            """)
    }

    /// Snapshots every parked window of an app now and shortly after, to catch apps that re-clamp windows later.
    private func traceApp(_ event: String, pid: pid_t) {
        let snapshot = { [weak self] (label: String) in
            guard let self else { return }
            for other in self.parked where other.window.pid == pid { self.trace("\(event) \(label)", other) }
        }
        snapshot("+0")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard self != nil else { return }
            snapshot("+400ms")
        }
    }
}
