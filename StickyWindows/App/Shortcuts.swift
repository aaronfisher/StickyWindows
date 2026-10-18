import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let parkFrontmostRight = Self("parkFrontmostRight", default: .init(.rightArrow, modifiers: [.control, .option, .command]))
    static let parkFrontmostLeft = Self("parkFrontmostLeft", default: .init(.leftArrow, modifiers: [.control, .option, .command]))
    static let parkFrontmostBottom = Self("parkFrontmostBottom", default: .init(.downArrow, modifiers: [.control, .option, .command]))

    static let parkShortcuts: [(name: Self, edge: Edge)] = [
        (.parkFrontmostLeft, .left), (.parkFrontmostRight, .right), (.parkFrontmostBottom, .bottom),
    ]
}
