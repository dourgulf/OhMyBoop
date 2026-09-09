// Created by lidawen.
import AppKit

@MainActor
final class LineNumberRuler: NSRulerView {
    private weak var editor: NSTextView?
    private(set) var lineStarts = [0]
    private var numberFont: NSFont {
        .monospacedDigitSystemFont(ofSize: max(10, (editor?.font?.pointSize ?? 14) - 2), weight: .regular)
    }
    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, editor: NSTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        setAccessibilityLabel(L10n.text("行号"))
        updateLineStarts()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Cache logical line starts on edits; scrolling only visits visible layout fragments.
    func updateLineStarts() {
        guard let editor else { return }
        let source = editor.string as NSString
        var starts = [0], offset = 0
        while offset < source.length {
            var end = 0
            source.getLineStart(nil, end: &end, contentsEnd: nil, for: NSRange(location: offset, length: 0))
            guard end > offset else { break }
            if end < source.length { starts.append(end) }
            offset = end
        }
        if source.length > 0, [10, 13, 0x2028, 0x2029].contains(source.character(at: source.length - 1)) {
            starts.append(source.length)
        }
        lineStarts = starts
        let width = max(44, (String(starts.count) as NSString).size(withAttributes: [.font: numberFont]).width + 20)
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }

    private func lineIndex(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }

    func visibleLabels() -> [(number: Int, y: CGFloat)] {
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return [] }
        let origin = editor.textContainerOrigin
        var visible = editor.visibleRect
        visible.origin.x -= origin.x
        visible.origin.y -= origin.y
        layout.ensureLayout(forBoundingRect: visible, in: container)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        var labels: [(number: Int, y: CGFloat)] = []
        layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, _ in
            let offset = layout.characterIndexForGlyph(at: range.location)
            let index = self.lineIndex(at: offset)
            // Wrapped continuation rows do not acquire new logical line numbers.
            guard self.lineStarts[index] == offset else { return }
            let point = self.convert(NSPoint(x: 0, y: rect.midY + origin.y), from: editor)
            labels.append((index + 1, point.y))
        }
        let length = (editor.string as NSString).length
        if lineStarts.last == length {
            var rect = layout.extraLineFragmentRect
            if rect.height == 0 {
                rect = NSRect(x: 0, y: 0, width: 0, height: layout.defaultLineHeight(for: editor.font ?? numberFont))
            }
            let point = convert(NSPoint(x: 0, y: rect.midY + origin.y), from: editor)
            if bounds.minY <= point.y && point.y <= bounds.maxY { labels.append((lineStarts.count, point.y)) }
        }
        return labels
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        (editor?.backgroundColor ?? .textBackgroundColor).setFill()
        bounds.intersection(rect).fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
        for label in visibleLabels() {
            let text = String(label.number) as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: ruleThickness - size.width - 10, y: label.y - size.height / 2), withAttributes: attributes)
        }
    }
}
