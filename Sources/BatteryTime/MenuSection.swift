// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit

/// A section heading that folds the rows below it away: its title and a
/// chevron that points down while folded and up while open, as Panes's and
/// Homestead's headings do. It is a view item, so clicking it leaves the menu
/// open. AppKit draws nothing for a view item, so it paints the native
/// highlight itself (the `.selection` material, at the native inset and
/// radius StatusItemKit's `ToggleMenuItem` uses).
final class DisclosureRow: NSView {
    private static let metrics = ToggleMenuMetrics.current
    /// Where a native submenu arrow ends, from the menu's right edge (Panes,
    /// measured on macOS 27).
    private static let trailingInset: CGFloat = 19

    var onClick: (() -> Void)?

    var expanded: Bool {
        didSet { if expanded != oldValue { updateChevron(animated: true) } }
    }

    private let selection = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let title: String

    /// `width` only seeds the frame: the row stretches to the menu's width.
    init(title: String, expanded: Bool, width: CGFloat = 200) {
        self.title = title
        self.expanded = expanded
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.metrics.height))
        autoresizingMask = [.width]

        selection.material = .selection
        selection.state = .active
        selection.isEmphasized = true
        selection.blendingMode = .behindWindow
        selection.maskImage = Self.roundedMask(radius: Self.metrics.highlightRadius)
        selection.frame = Self.metrics.highlightRect(in: bounds)
        selection.autoresizingMask = [.width]
        selection.isHidden = true
        addSubview(selection)

        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = title
        chevron.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        updateChevron(animated: false)

        for view in [label, chevron] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.metrics.titleX),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted == true }

    // The menu marks the row for display when its highlight changes.
    override func viewWillDraw() {
        selection.isHidden = !isHighlighted
        label.textColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        chevron.contentTintColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        super.viewWillDraw()
    }

    private func press() { onClick?() }

    private func updateChevron(animated: Bool) {
        guard let image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                  accessibilityDescription: nil) else { return }
        if animated, #available(macOS 14.0, *) {
            chevron.setSymbolImage(image, contentTransition: .replace.downUp)
        } else {
            chevron.image = image
        }
        needsDisplay = true
    }

    // MARK: Mouse

    // Take the first click though the menu window is not key, and take the
    // release: a view item that handles the mouse itself keeps the menu up.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        press()
    }

    // MARK: Keyboard

    // Arrow keys moving the highlight onto a view item ask whether it takes
    // first responder; say yes only then (not while the menu is opening).
    override var acceptsFirstResponder: Bool {
        NSApp.currentEvent?.type == .keyDown && window?.isVisible == true
    }

    override func keyDown(with event: NSEvent) {
        if isHighlighted, ToggleMenuKeys.toggles(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            press()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool { press(); return true }
    override func accessibilityRole() -> NSAccessibility.Role? { .disclosureTriangle }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityValue() -> Any? { NSNumber(value: expanded ? 1 : 0) }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A folding section of a menu: a `DisclosureRow` heading with its rows
/// below it while open. The state is remembered between openings under
/// `menuSection.<key>.expanded`; it starts folded.
enum MenuSection {
    static func add(title: String, key: String, items: [NSMenuItem], to menu: NSMenu) {
        let defaultsKey = "menuSection.\(key).expanded"
        let expanded = UserDefaults.standard.bool(forKey: defaultsKey)
        let header = NSMenuItem()
        let row = DisclosureRow(title: title, expanded: expanded)
        row.onClick = { [weak menu, weak header, weak row] in
            guard let menu, let header, let row else { return }
            row.expanded.toggle()
            UserDefaults.standard.set(row.expanded, forKey: defaultsKey)
            if row.expanded {
                let at = menu.index(of: header) + 1
                for (i, item) in items.enumerated() { menu.insertItem(item, at: at + i) }
            } else {
                for item in items where item.menu === menu { menu.removeItem(item) }
            }
        }
        header.view = row
        // AppKit drops the checkmark column when no item has a state, and the
        // native titles then move left of this row's. Saying `.on` keeps the
        // column, as StatusItemKit's ToggleMenuItem does; AppKit draws nothing
        // for a view item's state.
        header.state = .on
        menu.addItem(header)
        if expanded { items.forEach(menu.addItem) }
    }
}
