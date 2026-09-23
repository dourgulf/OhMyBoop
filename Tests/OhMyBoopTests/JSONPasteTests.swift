import AppKit
import XCTest
@testable import OhMyBoop

final class JSONPasteTests: XCTestCase {
    func testFormattingAndEscapes() throws {
        let expected = "{\n  \"a\": 1\n}"
        XCTAssertEqual(JSONPasteFormatter.format(#"{"a":1}"#), expected)
        XCTAssertEqual(JSONPasteFormatter.format(#"{\"a\":1}"#), expected)
        XCTAssertEqual(JSONPasteFormatter.format(#""{\"a\":1}""#), expected)
        let escapedValues = #"{"path":"C:\\temp","line":"a\nb","quote":"\"hi\"","url":"https://example.com"}"#
        let formatted = try XCTUnwrap(JSONPasteFormatter.format(escapedValues))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(formatted.utf8)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Data(escapedValues.utf8)) as? NSDictionary)
        XCTAssertEqual(JSONPasteFormatter.format(#"{\"broken\":}"#), #"{"broken":}"#)
        XCTAssertNil(JSONPasteFormatter.format("plain text"))
    }

    @MainActor func testNativePasteAction() throws {
        _ = NSApplication.shared
        let suite = "OhMyBoop.native-paste." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        preferences.automaticallyFormatJSONOnPaste = true
        let session = EditorSession(id: "json", draft: Draft(), preferences: preferences)
        let editor = try XCTUnwrap(session.scrollView.documentView as? HighlightTextView)
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer { board.clearContents(); board.writeObjects(saved) }
        board.clearContents()
        board.setString(#"{\"a\":1}"#, forType: .string)
        editor.paste(nil)
        XCTAssertEqual(session.text, "{\n  \"a\": 1\n}")
        // Generate escaped clipboard text from the reported missing-comma example.
        let malformed = """
        {
          "supplementaryPriceDesc": {
            "highlightedText": "Total {discountPrice}/year",
            "strikethroughText": "{productPrice}/year",
            "underlinePriceCoefficient": true
          },
          "topLabel": "Limited Time Offer",
          "subLabel": "You’ve come this far. nDon’t Lose Your Progress.",
          "discountDesc": "Save",
          "discount": "90%",
          "mainPriceDesc": {
            "text": "Only {productPrice} / week"
          }
          "test": true
        }
        """
        let escaped = malformed.replacingOccurrences(of: "\"", with: "\\\"")
        XCTAssertTrue(escaped.contains("\\"))
        editor.selectAll(nil)
        board.clearContents()
        board.setString(escaped, forType: .string)
        editor.paste(nil)
        XCTAssertEqual(session.text, malformed, "Remove slashes even when a missing comma prevents formatting")
    }

    @MainActor func testPastePreferenceScopeSelectionAndUndo() throws {
        _ = NSApplication.shared
        let suite = "OhMyBoop.paste-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        XCTAssertFalse(preferences.automaticallyFormatJSONOnPaste)
        let session = EditorSession(id: "json", draft: Draft(text: "before TARGET after"), preferences: preferences)
        let editor = try XCTUnwrap(session.scrollView.documentView as? HighlightTextView)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(#"{\"a\":1}"#, forType: .string)
        XCTAssertNil(editor.transformPastedText?(#"{\"a\":1}"#))
        preferences.automaticallyFormatJSONOnPaste = true
        XCTAssertTrue(EditorPreferences(defaults: defaults).automaticallyFormatJSONOnPaste)
        editor.setSelectedRange(NSRange(location: 7, length: 6))
        let undo = try XCTUnwrap(editor.undoManager)
        undo.beginUndoGrouping()
        XCTAssertTrue(editor.readSelection(from: board, type: .string))
        undo.endUndoGrouping()
        XCTAssertEqual(session.text, "before {\n  \"a\": 1\n} after")
        undo.undo()
        XCTAssertEqual(session.text, "before TARGET after")
        undo.redo()
        XCTAssertEqual(session.text, "before {\n  \"a\": 1\n} after")
        for id in ["text", "yaml"] {
            let other = EditorSession(id: id, draft: Draft(), preferences: preferences)
            let view = try XCTUnwrap(other.scrollView.documentView as? HighlightTextView)
            XCTAssertNil(view.transformPastedText?(#"{\"a\":1}"#))
        }
        preferences.automaticallyFormatJSONOnPaste = false
        XCTAssertNil(editor.transformPastedText?(#"{\"a\":1}"#))
        XCTAssertFalse(EditorPreferences(defaults: defaults).automaticallyFormatJSONOnPaste)
    }
}
