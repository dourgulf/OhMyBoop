import XCTest
import AppKit
import SwiftUI
@testable import OhMyBoop

final class EditorPreferencesTests: XCTestCase {
    @MainActor func testPersistenceFallbackAndReset() throws {
        let suite = "OhMyBoop.font-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        preferences.fontName = "Menlo-Regular"
        preferences.fontSize = 20
        let restored = EditorPreferences(defaults: defaults)
        XCTAssertEqual(restored.fontName, preferences.fontName)
        XCTAssertEqual(restored.fontSize, 20)
        preferences.fontSize = 999
        XCTAssertEqual(preferences.fontSize, 32)
        preferences.fontName = "missing-font"
        XCTAssertEqual(preferences.fontName, EditorPreferences.systemFontID)
        preferences.reset()
        XCTAssertEqual(EditorPreferences(defaults: defaults).fontSize, 14)
    }

    @MainActor func testChangingFontUpdatesAllPanesWithoutChangingTextSelectionOrUndo() throws {
        let suite = "OhMyBoop.font-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        let input = EditorSession(id: "json", draft: Draft(text: "{\"a\":1}"), preferences: preferences)
        let preview = EditorSession(id: "yaml", draft: Draft(text: "a:\t1"), isReadOnly: true, preferences: preferences)
        let editors = try [input, preview].map { try XCTUnwrap($0.scrollView.documentView as? HighlightTextView) }
        editors[0].setSelectedRange(NSRange(location: 2, length: 2))
        let oldText = editors.map(\.string)
        let oldSelection = editors[0].selectedRange()
        let oldUndo = editors[0].undoManager?.canUndo
        editors[0].showError(at: 4)
        preferences.fontSize = 24
        preferences.fontName = "Menlo-Regular"
        for editor in editors {
            XCTAssertEqual(editor.font?.pointSize, 24)
            XCTAssertEqual(editor.font?.fontName, preferences.font.fontName)
            let width = ("  " as NSString).size(withAttributes: [.font: preferences.font]).width
            XCTAssertEqual(editor.defaultParagraphStyle?.defaultTabInterval, width)
        }
        XCTAssertEqual(editors.map(\.string), oldText)
        XCTAssertEqual(editors[0].selectedRange(), oldSelection)
        XCTAssertEqual(editors[0].undoManager?.canUndo, oldUndo)
        XCTAssertEqual(editors[0].errorOffset, 4)
        XCTAssertFalse(editors[1].isEditable)
        input.replaceText("{\"updated\":true}")
        XCTAssertEqual(editors[0].font?.pointSize, 24, "Transformations must keep the chosen font")
        let later = EditorSession(id: "text", draft: Draft(), preferences: preferences)
        XCTAssertEqual((later.scrollView.documentView as? NSTextView)?.font?.pointSize, 24)
    }

    @MainActor func testSettingsNativePreviewAtLargestSize() throws {
        _ = NSApplication.shared
        let suite = "OhMyBoop.font-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorPreferences(defaults: defaults)
        preferences.fontSize = 32
        let hosting = NSHostingView(rootView: EditorSettingsView(preferences: preferences))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 610)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/ohmyboop-editor-settings-\(L10n.language).png"))
    }
}
