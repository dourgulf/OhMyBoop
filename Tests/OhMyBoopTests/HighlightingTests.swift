import XCTest
import AppKit
import SwiftUI
@testable import OhMyBoop

final class HighlightingTests: XCTestCase {
    func testLanguageSamplesAndThemesProduceColoredRanges() async {
        let samples = [
            "json": "{\"name\":\"你好 🌍 <>&\\\"\",\"n\":42,\"ok\":true}",
            "yaml": "name: hello\nitems:\n  - 123\n  - true",
            "xml": "<root id=\"1\"><item>Hello &amp; world</item></root>",
            "sql": "SELECT id FROM users WHERE id = 42; -- comment",
            "javascript": "const x = {name: 'hello', ok: true}; // comment",
            "css": "body { color: #ff0000; margin: 12px; }",
            "bash": "#!/bin/bash\necho \"$HOME\" # hello",
            "swift": "let message = \"你好\"\nprint(message)",
            "python": "def hello():\n    return True",
            "markdown": "# Title\n**bold** and `code`"
        ]
        let engine = HighlightEngine()
        for (language, source) in samples {
            for dark in [false, true] {
                let result = await engine.render(source, language: language, dark: dark)
                XCTAssertFalse(result.spans.isEmpty, "\(language): \(result.status)")
                XCTAssertTrue(result.spans.allSatisfy { NSMaxRange($0.range) <= source.utf16.count })
                XCTAssertGreaterThan(Set(result.spans.map { $0.color.description }).count, 1, language)
            }
        }
    }

    func testIncompleteInputEntitiesAndLineEndingsRemainSafe() async {
        let engine = HighlightEngine()
        for text in ["{\"incomplete\":", "{\n\"emoji\": \"👨‍👩‍👧‍👦 e\u{301}\"\n}", "a\r\nb\rc\n", "<>&amp;&#123;\"'", "\t\t leading\n\n", "\u{0}test"] {
            let result = await engine.render(text, language: "json", dark: false)
            // The adapter only emits ranges after exact UTF-16 equality; any upstream
            // HTML normalization must become a plain-text fallback rather than editing input.
            XCTAssertTrue(!result.spans.isEmpty || result.status.contains("纯文本"), result.status)
        }
        let invalid = await engine.render("hello", language: "does-not-exist", dark: false)
        XCTAssertTrue(invalid.spans.isEmpty)
        XCTAssertTrue(invalid.status.contains("不支持"))
        let large = await engine.render(String(repeating: "a", count: 100_001), language: "json", dark: false)
        XCTAssertTrue(large.spans.isEmpty)
        let autoLarge = await engine.render(String(repeating: "a", count: 8_001), language: nil, dark: false)
        XCTAssertTrue(autoLarge.status.contains("指定语言"))
    }

    @MainActor
    private func awaitHighlight(_ editor: HighlightTextView) async throws {
        let previous = editor.lastAppliedGeneration
        editor.scheduleHighlight()
        let deadline = Date().addingTimeInterval(10)
        while editor.lastAppliedGeneration == previous && Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertGreaterThan(editor.lastAppliedGeneration, previous)
    }

    @MainActor func testHighlightDoesNotChangeTextSelectionScrollOrUndo() async throws {
        let session = EditorSession(id: "FormatJSON", draft: Draft())
        let editor = session.scrollView.documentView as! HighlightTextView
        let source = "[\n" + Array(repeating: "{\"name\":\"hello\",\"n\":42}", count: 30).joined(separator: ",\n") + "\n]"
        session.replaceText(source, selection: NSRange(location: 2, length: 4))
        session.scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        session.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        let before = session.snapshot()
        XCTAssertGreaterThan(before.scrollY, 0)
        let undo = try XCTUnwrap(editor.undoManager)
        let canUndo = undo.canUndo
        try await awaitHighlight(editor)
        XCTAssertEqual(session.snapshot(), before)
        XCTAssertEqual(editor.string, before.text)
        XCTAssertEqual(undo.canUndo, canUndo)
        XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 2, effectiveRange: nil))
        XCTAssertEqual(editor.textStorage?.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, .textColor)
        undo.undo()
        XCTAssertEqual(editor.string, "")
        undo.redo()
        XCTAssertEqual(editor.string, before.text)
        try await awaitHighlight(editor)
        session.highlightLanguage = .plaintext
        XCTAssertNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 2, effectiveRange: nil))
    }

    @MainActor func testRapidEditsAndMarkedTextRejectStaleResults() async throws {
        let editor = HighlightTextView(frame: .zero)
        editor.language = .json
        editor.string = "{\"first\":1}"
        editor.scheduleHighlight()
        editor.string = "{\"last\":true}"
        try await awaitHighlight(editor)
        XCTAssertEqual(editor.string, "{\"last\":true}")
        let applied = editor.lastAppliedGeneration
        editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
        editor.scheduleHighlight()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(editor.lastAppliedGeneration, applied)
        editor.unmarkText()
        try await awaitHighlight(editor)
    }

    @MainActor func testIndependentLanguagePreferencesAndOldDraftCompatibility() throws {
        let legacy = try JSONDecoder().decode(Draft.self, from: Data("{\"text\":\"old\",\"selectionLocation\":0,\"selectionLength\":0,\"scrollY\":0}".utf8))
        XCTAssertNil(legacy.highlightLanguage)
        let a = EditorSession(id: "FormatJSON", draft: legacy)
        let b = EditorSession(id: "Base64Decode", draft: Draft())
        a.highlightLanguage = .yaml
        b.highlightLanguage = .plaintext
        _ = a.scrollView
        _ = b.scrollView
        let restored = try JSONDecoder().decode(Draft.self, from: JSONEncoder().encode(a.snapshot()))
        XCTAssertEqual(EditorSession(id: "FormatJSON", draft: restored).highlightLanguage, .yaml)
        XCTAssertEqual(b.highlightLanguage, .plaintext)
    }

    @MainActor func testCaptureLightAndDarkEditor() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        for dark in [false, true] {
            let workspace = Workspace(storage: DraftStorage(url: folder.appendingPathComponent("draft.json")))
            let session = workspace.session(for: "FormatJSON")
            session.replaceText("{\n  \"app\": \"OhMyBoop\",\n  \"message\": \"你好，世界 🌍\",\n  \"tools\": 72,\n  \"highlighting\": true,\n  \"items\": [\"JSON\", \"YAML\", \"SQL\"],\n  \"optional\": null\n}")
            let hosting = NSHostingView(rootView: ContentView(workspace: workspace).environment(\.colorScheme, dark ? .dark : .light))
            hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            hosting.frame = NSRect(x: 0, y: 0, width: 1120, height: 740)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            try await awaitHighlight(session.scrollView.documentView as! HighlightTextView)
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/ohmyboop-highlighting-\(dark ? "dark" : "light").png"))
            window.orderOut(nil)
        }
    }

    func testOptInPerformanceSamples() async throws {
        guard ProcessInfo.processInfo.environment["OHMYBOOP_BENCHMARK"] == "1" else { throw XCTSkip("Set OHMYBOOP_BENCHMARK=1 for full rendering benchmarks") }
        let engine = HighlightEngine()
        for size in [10_000, 100_000, 1_000_000] {
            let source = "[" + Array(repeating: "{\"name\":\"hello\",\"n\":42,\"ok\":true}", count: size / 35).joined(separator: ",\n") + "]"
            let result = await engine.render(source, language: "json", dark: false, enforceLimit: false)
            XCTAssertFalse(result.spans.isEmpty)
            print("BENCH explicit JSON utf16=\(source.utf16.count) ms=\(result.milliseconds) ranges=\(result.spans.count)")
        }
        let source = String(repeating: "let count = 42; // sample\n", count: 100)
        let result = await engine.render(source, language: nil, dark: false, enforceLimit: false)
        print("BENCH automatic utf16=\(source.utf16.count) ms=\(result.milliseconds) ranges=\(result.spans.count)")
    }
}
