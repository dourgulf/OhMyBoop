import XCTest
import AppKit
import SwiftUI
@testable import OhMyBoop

final class HighlightingTests: XCTestCase {
    @MainActor func testTabInsertsTwoSpacesWithUndoAndRespectsReadOnly() throws {
        let session = EditorSession(id: "json", draft: Draft(text: "{}"))
        let editor = try XCTUnwrap(session.scrollView.documentView as? HighlightTextView)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        let undo = try XCTUnwrap(editor.undoManager)
        undo.beginUndoGrouping()
        editor.insertTab(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(session.text, "{  }")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 0))
        undo.undo()
        XCTAssertEqual(session.text, "{}")
        let expectedWidth = ("  " as NSString).size(withAttributes: [.font: editor.font!]).width
        XCTAssertEqual(editor.defaultParagraphStyle?.defaultTabInterval, expectedWidth)
        XCTAssertTrue(editor.defaultParagraphStyle?.tabStops.isEmpty == true)
        editor.isEditable = false
        editor.insertTab(nil)
        XCTAssertEqual(session.text, "{}")
    }

    func testScalarTypesHaveDistinctEffectiveColorsInBothThemes() async throws {
        let samples = [
            "json": "{\"title\":\"hello\",\"count\":42,\"enabled\":true,\"missing\":null}",
            "yaml": "title: hello\ncount: 42\nenabled: true\nmissing: null\n",
        ]
        for (language, source) in samples {
            for dark in [false, true] {
                let result = await HighlightEngine().render(source, language: language, dark: dark)
                // Resolve the final painted color, including overlapping key/string captures.
                let colors = try ["title", "hello", "42", "true", "null"].map { token in
                    let offset = (source as NSString).range(of: token).location
                    return try XCTUnwrap(result.spans.last { NSLocationInRange(offset, $0.range) }?.color)
                }
                XCTAssertEqual(Set(colors.prefix(4).map { $0.description }).count, 4, "\(language), dark=\(dark)")
                XCTAssertEqual(colors[3], colors[4], "Boolean and null share the literal color")
            }
        }
    }

    func testLanguageSamplesAndThemesProduceColoredRanges() async {
        let samples = [
            "json": "{\"name\":\"你好 🌍 <>&\\\"\",\"n\":42,\"ok\":true}",
            "yaml": "name: hello\nitems:\n  - 123\n  - true",
            "javascript": "const x = {name: 'hello', ok: true}; // comment",
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
            // Tree-sitter offsets are UTF-16 ranges over the original input.
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

    func testIncrementalEditsMatchFreshParseAcrossUnicodeAndLanguageChanges() async {
        let engine = HighlightEngine()
        let samples: [(String, [String])] = [
            ("json", ["{\"name\":\"😀\",\"n\":42}", "{\"name\":\"😁\",\"n\":42}", "{\r\n\"name\":\"你好 e\u{301}\",\"n\":4}", "{\"name\":", "[]", "", "[true,null]"]),
            ("yaml", ["key: hello\nitems:\n  - true", "key: '🌍'\nitems:\n  - 123\n  - false", "key:"]),
            ("javascript", ["const x = 'hello'; // comment", "const x = `🌍`;\n/* comment */", "function f() { return 42; }", "function f( {", "const f = () => true;"])
        ]
        for (language, edits) in samples {
            for (index, text) in edits.enumerated() {
                let actual = await engine.render(text, language: language, dark: false)
                let fresh = await HighlightEngine().render(text, language: language, dark: false)
                XCTAssertEqual(actual.spans.map(\.range), fresh.spans.map(\.range), "\(language) edit \(index)")
                XCTAssertEqual(actual.spans.map { $0.color.description }, fresh.spans.map { $0.color.description })
                if index == 1 { XCTAssertTrue(actual.incremental) }
                if index == 0 { XCTAssertFalse(actual.incremental) }
            }
        }
    }

    func testViewportMatchesFullHighlightAcrossMultilineSyntaxAndEdits() async {
        let samples = [
            ("javascript", "/* start\n" + String(repeating: "你好 🌍 comment\n", count: 80) + "*/\nconst message = `first\nsecond 🌍\nlast`;"),
            ("yaml", "message: |\n" + String(repeating: "  hello 🌍\n", count: 80) + "enabled: true\n"),
            ("json", "[" + Array(repeating: "{\"name\":\"🌍\",\"n\":42}", count: 80).joined(separator: ",\n") + "]")
        ]
        for (language, text) in samples {
            let engine = HighlightEngine()
            for source in [text, "\n" + text, String(text.dropFirst(2))] {
                for dark in [false, true] {
                    let full = await HighlightEngine().render(source, language: language, dark: dark)
                    for range in [NSRange(location: 0, length: 100), NSRange(location: 250, length: 120), NSRange(location: source.utf16.count - 80, length: 80)] {
                        let visible = await engine.render(source, language: language, dark: dark, visibleRange: range)
                        let expected = full.spans.compactMap { span -> HighlightSpan? in
                            let clipped = NSIntersectionRange(span.range, range)
                            return clipped.length > 0 ? HighlightSpan(range: clipped, color: span.color) : nil
                        }
                        XCTAssertEqual(visible.spans.map(\.range), expected.map(\.range), language)
                        XCTAssertEqual(visible.spans.map { $0.color }, expected.map { $0.color }, language)
                    }
                }
            }
        }
    }

    @MainActor func testViewportScrollRecolorsWithoutChangingDocumentAndClearsOnFallback() async throws {
        let source = "[\n" + Array(repeating: "{\"name\":\"hello 🌍\",\"n\":42}", count: 1500).joined(separator: ",\n") + "\n]"
        let session = EditorSession(id: "FormatJSON", draft: Draft(text: source))
        let scroll = session.scrollView
        scroll.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        let editor = scroll.documentView as! HighlightTextView
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        try await awaitHighlight(editor)
        let first = try XCTUnwrap(editor.lastAppliedRange)
        XCTAssertLessThan(first.length, source.utf16.count / 4)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 4000))
        let snapshot = session.snapshot()
        let previousGeneration = editor.lastAppliedGeneration
        // Exercise the bounds notification path without manually scheduling a text change.
        let deadline = Date().addingTimeInterval(10)
        while editor.lastAppliedGeneration == previousGeneration && Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertGreaterThan(editor.lastAppliedGeneration, previousGeneration)
        let second = try XCTUnwrap(editor.lastAppliedRange)
        XCTAssertGreaterThan(second.location, NSMaxRange(first))
        XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: second.location, effectiveRange: nil))
        XCTAssertNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
        XCTAssertEqual(session.snapshot(), snapshot)
        scroll.frame.size.height = 500
        try await awaitHighlight(editor)
        let resized = try XCTUnwrap(editor.lastAppliedRange)
        XCTAssertGreaterThan(resized.length, second.length)
        session.replaceText("{\"updated\":true}")
        scroll.contentView.scroll(to: .zero)
        try await awaitHighlight(editor)
        XCTAssertEqual(editor.lastAppliedRange, NSRange(location: 0, length: editor.string.utf16.count))
        session.highlightLanguage = .plaintext
        XCTAssertNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
        XCTAssertNil(editor.lastAppliedRange)
    }

    func testDocumentIsolationAndConservativeAutomaticMode() async {
        let a = HighlightEngine(), b = HighlightEngine()
        _ = await a.render("{\"a\":1}", language: "json", dark: false)
        let firstB = await b.render("{\"b\":2}", language: "json", dark: false)
        XCTAssertFalse(firstB.incremental)
        let editedA = await a.render("{\"a\":3}", language: "json", dark: true)
        XCTAssertTrue(editedA.incremental)
        let automatic = await a.render("[1, true]", language: nil, dark: false)
        XCTAssertTrue(automatic.status.contains("JSON"))
        let arbitrary = await a.render("ordinary prose: hello", language: nil, dark: false)
        XCTAssertTrue(arbitrary.spans.isEmpty)
        XCTAssertTrue(arbitrary.status.contains("请选择语言"))
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

    @MainActor func testOptInViewportApplicationSamples() async throws {
        guard ProcessInfo.processInfo.environment["OHMYBOOP_BENCHMARK"] == "1" else { throw XCTSkip("Set OHMYBOOP_BENCHMARK=1 for viewport benchmarks") }
        let source = "[\n" + Array(repeating: "{\"name\":\"hello\",\"n\":42}", count: 3500).joined(separator: ",\n") + "\n]"
        let session = EditorSession(id: "FormatJSON", draft: Draft(text: source))
        session.scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        let editor = session.scrollView.documentView as! HighlightTextView
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        var samples: [Double] = []
        for index in 0..<20 {
            session.scrollView.contentView.scroll(to: NSPoint(x: 0, y: index * 1000))
            try await awaitHighlight(editor)
            XCTAssertNotNil(editor.lastAppliedRange)
            samples.append(editor.lastApplicationMilliseconds)
        }
        samples.sort()
        print("BENCH viewport UI application utf16=\(source.utf16.count) samples=20 median_ms=\(samples[10]) p95_ms=\(samples[18])")
    }

    func testOptInPerformanceSamples() async throws {
        guard ProcessInfo.processInfo.environment["OHMYBOOP_BENCHMARK"] == "1" else { throw XCTSkip("Set OHMYBOOP_BENCHMARK=1 for full rendering benchmarks") }
        for size in [10_000, 100_000, 1_000_000] {
            let engine = HighlightEngine()
            let source = "[" + Array(repeating: "{\"name\":\"hello\",\"n\":42,\"ok\":true}", count: size / 35).joined(separator: ",\n") + "]"
            let result = await engine.render(source, language: "json", dark: false, enforceLimit: false)
            XCTAssertFalse(result.spans.isEmpty)
            print("BENCH full JSON utf16=\(source.utf16.count) ms=\(result.milliseconds) parse=\(result.parseMilliseconds) ranges=\(result.spans.count)")
            let edited = String(source.dropLast()) + " "+"]"
            let edit = await engine.render(edited, language: "json", dark: false, enforceLimit: false)
            XCTAssertTrue(edit.incremental)
            print("BENCH edit JSON utf16=\(edited.utf16.count) ms=\(edit.milliseconds) parse=\(edit.parseMilliseconds)")
            var samples: [Double] = []
            for index in 0..<20 {
                let sample = String(source.dropLast()) + (index.isMultiple(of: 2) ? " " : "  ") + "]"
                let viewport = await engine.render(sample, language: "json", dark: false, enforceLimit: false,
                    visibleRange: NSRange(location: max(0, sample.utf16.count - 3000), length: 3000))
                XCTAssertFalse(viewport.spans.isEmpty)
                samples.append(viewport.milliseconds)
            }
            samples.sort()
            print("BENCH viewport edit JSON utf16=\(source.utf16.count) samples=20 median_ms=\(samples[10]) p95_ms=\(samples[18])")
        }
        let engine = HighlightEngine()
        let source = String(repeating: "let count = 42; // sample\n", count: 100)
        let result = await engine.render(source, language: nil, dark: false, enforceLimit: false)
        print("BENCH automatic utf16=\(source.utf16.count) ms=\(result.milliseconds) ranges=\(result.spans.count)")
    }
}
