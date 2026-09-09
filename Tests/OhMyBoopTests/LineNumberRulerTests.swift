import XCTest
import AppKit
@testable import OhMyBoop

final class LineNumberRulerTests: XCTestCase {
    @MainActor func testLogicalLinesAndUndoIncludeTrailingEmptyLine() throws {
        let session = EditorSession(id: "json", draft: Draft(text: "😀\r\nsecond\rthird\n"))
        let ruler = try XCTUnwrap(session.scrollView.verticalRulerView as? LineNumberRuler)
        XCTAssertEqual(ruler.lineStarts, [0, 4, 11, 17])
        session.replaceText("")
        XCTAssertEqual(ruler.lineStarts, [0])
        (session.scrollView.documentView as? NSTextView)?.undoManager?.undo()
        XCTAssertEqual(ruler.lineStarts, [0, 4, 11, 17])
        session.replaceText(Array(repeating: "x", count: 10_000).joined(separator: "\n"))
        XCTAssertEqual(ruler.lineStarts.count, 10_000)
        XCTAssertGreaterThan(ruler.ruleThickness, 44)
    }

    @MainActor func testWrappedLinesAndScrollingUseLogicalNumbersInReadOnlyPane() throws {
        _ = NSApplication.shared
        let source = String(repeating: "long text ", count: 25) + "\n" + (2...150).map { "line \($0)" }.joined(separator: "\n")
        let session = EditorSession(id: "text", draft: Draft(text: source), isReadOnly: true)
        let scroll = session.scrollView
        scroll.frame = NSRect(x: 0, y: 0, width: 320, height: 250)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.orderOut(nil) }
        scroll.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(scroll.documentView as? NSTextView)
        let ruler = try XCTUnwrap(scroll.verticalRulerView as? LineNumberRuler)
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        session.restoreScroll()
        XCTAssertEqual(scroll.contentView.bounds.minX, -scroll.contentView.contentInsets.left)
        let labels = ruler.visibleLabels()
        XCTAssertEqual(labels.first?.number, 1)
        let first = try XCTUnwrap(labels.first { $0.number == 1 })
        let second = try XCTUnwrap(labels.first { $0.number == 2 })
        XCTAssertGreaterThan(second.y - first.y, 50, "Wrapped continuation rows must not be numbered as new lines")
        XCTAssertEqual(Set(labels.map(\.number)).count, labels.count)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1200))
        XCTAssertGreaterThan(try XCTUnwrap(ruler.visibleLabels().first?.number), 2)
        XCTAssertEqual(editor.string, source)
        XCTAssertFalse(editor.isEditable)
    }
}
