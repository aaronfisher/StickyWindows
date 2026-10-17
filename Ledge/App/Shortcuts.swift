import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Park the frontmost window to the right edge (M2). A recorder for it lands with the settings window.
    static let parkFrontmostRight = Self("parkFrontmostRight", default: .init(.rightArrow, modifiers: [.control, .option, .command]))
}
