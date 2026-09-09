import XCTest
import AppKit
@testable import OhMyBoop

final class JSONDiagnosticsTests: XCTestCase {
    func testChineseCommaIsIdentifiedWithoutRejectingStringContent() throws {
        for source in ["{\"a\":1，\"b\":2}", "[1，2]", "{\n  \"😀\": true ，\n  \"b\": null\n}"] {
            let result = try ScriptEngine.execute(ScriptRequest(toolID: "FormatJSON", text: source, selectionLocation: 0, selectionLength: 0, language: "zh-Hans"))
            XCTAssertEqual(result.errorOffset, (source as NSString).range(of: "，").location)
            XCTAssertEqual(result.error, "使用了中文逗号“，”，请改为英文逗号“,”")
            XCTAssertEqual(result.text, source)
        }
        let valid = try ScriptEngine.execute(ScriptRequest(toolID: "FormatJSON", text: "{\"描述，备注\":\"你好，世界\"}", selectionLocation: 0, selectionLength: 0, language: "zh-Hans"))
        XCTAssertNil(valid.error)
        XCTAssertTrue(valid.text.contains("你好，世界"))
        let otherError = "{\"text\":\"你好，世界\",\"n\" 1}"
        let result = try ScriptEngine.execute(ScriptRequest(toolID: "FormatJSON", text: otherError, selectionLocation: 0, selectionLength: 0, language: "zh-Hans"))
        XCTAssertTrue(result.error?.contains("冒号") == true)
        XCTAssertEqual(result.errorOffset, (otherError as NSString).range(of: "1").location)
    }

    private var executable: URL {
        Catalog.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("OhMyBoop")
    }

    func testSyntaxFailuresPreserveInputAndLocateFirstError() throws {
        let samples: [(String, Int, String)] = [
            ("{\"a\":1,}", 6, "逗号"),
            ("{\"a\" 1}", 5, "冒号"),
            ("{\"a\":1 \"b\":2}", 6, "逗号"),
            ("{\n  \"a\": 1,\n}", 10, "逗号"),
            ("{\n  \"a\": 1\n  \"b\": 2\n}", 10, "逗号"),
            ("[\r\n  1,\r\n]", 6, "逗号"),
            ("[\r\n  1\r\n  2\r\n]", 6, "逗号"),
            ("[1}", 2, "结束符"),
            ("{\"a\":1", 6, "结束符"),
            ("", 0, "JSON 值"),
            ("'hello'", 0, "双引号"),
            ("[01]", 2, "前导零"),
            ("[1.]", 3, "小数点"),
            ("[1e+]", 4, "指数"),
            ("[truX]", 4, "true"),
            ("[/*hi*/1]", 1, "注释"),
            ("\"abc", 4, "双引号"),
            ("\"a\\q\"", 3, "转义"),
            ("\"\\u12x4\"", 5, "Unicode"),
            ("\"a\nb\"", 2, "控制字符"),
            ("{} []", 3, "多余内容"),
        ]
        for (source, offset, reason) in samples {
            // A caret away from the start must not shift whole-document diagnostics.
            let result = try ScriptEngine.execute(ScriptRequest(toolID: "FormatJSON", text: source, selectionLocation: min(2, source.utf16.count), selectionLength: 0, language: "zh-Hans"))
            XCTAssertEqual(result.text, source)
            XCTAssertEqual(result.errorOffset, offset, source)
            XCTAssertTrue(result.error?.contains(reason) == true, "\(source): \(result.error ?? "nil")")
        }
    }

    func testNativeParserRemainsAuthorityForValidJSON() throws {
        for source in ["null", "42", "true", "\"😀\\u1234\"", "[0,-1.2e+3]", "{\"a\":1,\"a\":2}"] {
            let result = try ScriptEngine.execute(ScriptRequest(toolID: "FormatJSON", text: source, selectionLocation: 0, selectionLength: 0, language: "zh-Hans"))
            XCTAssertNil(result.error)
            XCTAssertNil(result.errorOffset)
        }
    }

    @MainActor func testMultilineCommaMessagesMatchTheMarkedLine() async throws {
        let action = try XCTUnwrap(FormatCatalog.action("FormatJSON"))
        for source in ["{\n  \"a\": 1,\n}", "{\n  \"a\": 1\n  \"b\": 2\n}", "[\r\n  1,\r\n]", "[\r\n  1\r\n  2\r\n]"] {
            let session = EditorSession(id: "json", draft: Draft(text: source))
            let editor = try XCTUnwrap(session.scrollView.documentView as? HighlightTextView)
            let ruler = try XCTUnwrap(session.scrollView.verticalRulerView as? LineNumberRuler)
            await session.perform(action, executableURL: executable)
            XCTAssertTrue(session.message?.hasPrefix(L10n.text("第 %@ 行，第 %@ 列：%@", "2", "", "").components(separatedBy: L10n.language == "en" ? "," : "，")[0]) == true, session.message ?? "")
            let offset = try XCTUnwrap(editor.errorOffset)
            XCTAssertGreaterThanOrEqual(offset, ruler.lineStarts[1])
            XCTAssertLessThan(offset, ruler.lineStarts[2])
            XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil))
            XCTAssertEqual(session.text, source)
        }
    }

    @MainActor func testSelectedErrorUsesDocumentCoordinatesAndClearsAfterEditing() async throws {
        _ = NSApplication.shared
        let source = "说明😀\r\n{\"😀\": 1,}\r\n尾部"
        let selected = (source as NSString).range(of: "{\"😀\": 1,}")
        let session = EditorSession(id: "json", draft: Draft(text: source, selectionLocation: selected.location, selectionLength: selected.length))
        let editor = try XCTUnwrap(session.scrollView.documentView as? HighlightTextView)
        let undo = try XCTUnwrap(editor.undoManager)
        let oldUndo = undo.canUndo
        let action = try XCTUnwrap(FormatCatalog.action("FormatJSON"))
        await session.perform(action, executableURL: executable)
        let offset = (source as NSString).range(of: ",").location
        XCTAssertEqual(editor.errorOffset, offset)
        XCTAssertTrue(session.message == L10n.text("第 %@ 行，第 %@ 列：%@", "2", "8", L10n.text("最后一项后不能有多余的逗号")), session.message ?? "")
        XCTAssertEqual(session.text, source)
        XCTAssertEqual(editor.selectedRange(), selected)
        XCTAssertEqual(undo.canUndo, oldUndo)
        XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil))
        editor.language = .plaintext
        XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil))
        session.replaceText("{\"fixed\":true}")
        XCTAssertNil(editor.errorOffset)
        XCTAssertNil(session.message)
        await session.perform(action, executableURL: executable)
        XCTAssertFalse(session.isError)
        XCTAssertNil(editor.errorOffset)
    }

    @MainActor func testEOFAndEmptyDocumentHaveMarkersAndNativePreviews() async throws {
        _ = NSApplication.shared
        let action = try XCTUnwrap(FormatCatalog.action("FormatJSON"))
        for dark in [false, true] {
            for (name, source) in [("character", "{\n  \"name\": \"OhMyBoop\",\n  \"count\": 42,\n  \"enabled\": true,\n}"), ("eof", "{\n  \"name\": \"OhMyBoop\"\n"), ("empty", ""), ("newline", "{\"name\": \"hello\nworld\"}")] {
                let session = EditorSession(id: "json", draft: Draft(text: source))
                let scroll = session.scrollView
                scroll.frame = NSRect(x: 0, y: 0, width: 700, height: 260)
                let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = scroll
                let editor = try XCTUnwrap(scroll.documentView as? HighlightTextView)
                await session.perform(action, executableURL: executable)
                XCTAssertNotNil(editor.errorOffset)
                if name == "eof" || name == "empty" {
                    XCTAssertEqual(editor.errorOffset, source.utf16.count)
                    XCTAssertTrue(session.message?.hasSuffix(L10n.text("%@（文本末尾）", "")) == true)
                }
                try await Task.sleep(for: .milliseconds(400))
                scroll.layoutSubtreeIfNeeded()
                // Background decoration must survive asynchronous syntax recoloring.
                if name == "character" {
                    XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: editor.errorOffset!, effectiveRange: nil))
                }
                let bitmap = try XCTUnwrap(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
                scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: "/tmp/ohmyboop-json-error-\(name)-\(dark ? "dark" : "light").png"))
                window.orderOut(nil)
            }
        }
    }
}
