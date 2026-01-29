import AppKit
import CoreText

class ListView: NSView {
    var items: [String] = []
    var selected: Int = 0
    var scrollOffset: CGFloat = 0
    var rowHeight: CGFloat = 28
    var padding: CGFloat = 8
    var maxVisible: Int = 12

    var bgColor: NSColor = .clear
    var fgColor: NSColor = .white
    var hiColor: NSColor = .blue

    var onClick: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?

    private var lineCache: [String: CTLine] = [:]
    private var normalAttrs: [NSAttributedString.Key: Any] = [:]
    private var selectedAttrs: [NSAttributedString.Key: Any] = [:]
    private var trackingArea: NSTrackingArea?
    private var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        updateAttrs()
    }

    func updateAttrs() {
        normalAttrs = [
            .font: font,
            .foregroundColor: fgColor
        ]
        selectedAttrs = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        lineCache.removeAll()
    }

    func updateColors(bg: NSColor, fg: NSColor, hi: NSColor) {
        bgColor = bg
        fgColor = fg
        hiColor = hi
        updateAttrs()
        needsDisplay = true
    }

    func setItems(_ newItems: [String]) {
        items = newItems
        scrollOffset = 0
        selected = 0
        lineCache.removeAll()
        needsDisplay = true
    }

    func reset() {
        scrollOffset = 0
        selected = 0
        needsDisplay = true
    }

    func select(_ index: Int) {
        guard index >= 0 && index < items.count else { return }
        selected = index
        ensureVisible(index)
        needsDisplay = true
    }

    func moveSelection(_ delta: Int) {
        let newIndex = max(0, min(selected + delta, items.count - 1))
        if newIndex != selected {
            selected = newIndex
            ensureVisible(newIndex)
            needsDisplay = true
        }
    }

    private func ensureVisible(_ index: Int) {
        let itemY = CGFloat(index) * rowHeight
        let viewHeight = CGFloat(maxVisible) * rowHeight

        if itemY < scrollOffset {
            scrollOffset = itemY
        } else if itemY + rowHeight > scrollOffset + viewHeight {
            scrollOffset = itemY + rowHeight - viewHeight
        }
    }

    private func getLine(_ text: String, selected: Bool) -> CTLine {
        let key = "\(text)_\(selected)"
        if let cached = lineCache[key] {
            return cached
        }
        let attrs = selected ? selectedAttrs : normalAttrs
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        lineCache[key] = line
        return line
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(bounds)

        let visibleStart = Int(scrollOffset / rowHeight)
        let visibleEnd = min(visibleStart + maxVisible + 1, items.count)

        for i in visibleStart..<visibleEnd {
            let y = CGFloat(i) * rowHeight - scrollOffset
            let rect = NSRect(x: 0, y: y, width: bounds.width, height: rowHeight)

            if i == selected {
                ctx.setFillColor(hiColor.cgColor)
                ctx.fill(rect)
            }

            let text = items[i]
            let line = getLine(text, selected: i == selected)

            ctx.saveGState()
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            let textY = y + 18
            ctx.textPosition = CGPoint(x: padding, y: textY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let index = Int((loc.y + scrollOffset) / rowHeight)
        if index >= 0 && index < items.count && index != selected {
            selected = index
            needsDisplay = true
            onHover?(index)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let index = Int((loc.y + scrollOffset) / rowHeight)
        if index >= 0 && index < items.count {
            selected = index
            needsDisplay = true
            onClick?(index)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let maxScroll = max(0, CGFloat(items.count) * rowHeight - CGFloat(maxVisible) * rowHeight)
        scrollOffset = max(0, min(scrollOffset - event.scrollingDeltaY, maxScroll))
        needsDisplay = true
    }

    func height() -> CGFloat {
        CGFloat(min(items.count, maxVisible)) * rowHeight
    }
}
