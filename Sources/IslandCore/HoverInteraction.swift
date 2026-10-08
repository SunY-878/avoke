import Foundation

public enum HoverAction { case expand, collapse }

/// Time-based hover behavior, independent of windowing and mouse permissions.
public struct HoverInteraction {
    private var enteredAt: TimeInterval?
    private var leftAt: TimeInterval?
    private var requiresExit = false
    public init() {}

    public mutating func didClose() {
        enteredAt = nil; leftAt = nil; requiresExit = true
    }
    public mutating func holdOpen() { leftAt = nil }

    public mutating func update(inside: Bool, expanded: Bool, pinned: Bool, heldOpen: Bool,
                                now: TimeInterval, hoverDelay: TimeInterval) -> HoverAction? {
        if inside {
            leftAt = nil
            guard !expanded, !requiresExit else { enteredAt = nil; return nil }
            if enteredAt == nil { enteredAt = now }
            if now - enteredAt! >= hoverDelay { enteredAt = nil; return .expand }
        } else {
            requiresExit = false; enteredAt = nil
            guard expanded, !pinned, !heldOpen else { leftAt = nil; return nil }
            if leftAt == nil { leftAt = now }
            if now - leftAt! >= 0.48 { leftAt = nil; return .collapse }
        }
        return nil
    }
}
