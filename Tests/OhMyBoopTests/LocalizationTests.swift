import XCTest
import AppKit
import SwiftUI
@testable import OhMyBoop

final class LocalizationTests: XCTestCase {
    func testLanguageSelectionPersistenceAndSystemFallback() throws {
        XCTAssertEqual(L10n.resolveLanguage("system", preferred: ["zh-Hans-CN", "en"]), "zh-Hans")
        XCTAssertEqual(L10n.resolveLanguage("system", preferred: ["en-US", "zh-Hans"]), "en")
        XCTAssertEqual(L10n.resolveLanguage("en", preferred: ["zh-Hans"]), "en")
        XCTAssertEqual(L10n.resolveLanguage(nil, preferred: ["fr-FR"]), "en")
        let suite = "OhMyBoop.localization." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        L10n.saveLanguage("zh-Hans", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: L10n.preferenceKey), "zh-Hans")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
        L10n.saveLanguage("system", defaults: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
    }

    func testBothResourceTablesCoverAllActionsAndHaveMatchingPlaceholders() throws {
        func table(_ language: String) throws -> [String: String] {
            let url = try XCTUnwrap(L10n.bundle(for: language).url(forResource: "Localizable", withExtension: "strings"))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let english = try table("en"), chinese = try table("zh-Hans")
        XCTAssertGreaterThan(english.count, 150)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        for key in english.keys {
            XCTAssertEqual(english[key]!.components(separatedBy: "%@").count, chinese[key]!.components(separatedBy: "%@").count, key)
        }
        for key in FormatCatalog.actions.flatMap({ [$0.title, $0.group] }) + FormatCatalog.formats.map(\.title) where key.range(of: "\\p{Han}", options: .regularExpression) != nil {
            XCTAssertNotNil(english[key], key)
        }
        XCTAssertEqual(L10n.text("格式化", language: "en"), "Format")
        XCTAssertEqual(L10n.text("格式化", language: "zh-Hans"), "格式化")
        XCTAssertEqual(L10n.text("第 %@ 行，第 %@ 列：%@", "2", "8", "Bad input", language: "en"), "Line 2, column 8: Bad input")
        XCTAssertEqual(L10n.scriptMessage("1 words", language: "en"), "Words: 1")
        XCTAssertEqual(L10n.scriptMessage("2 words", language: "zh-Hans"), "词数：2")
        XCTAssertEqual(L10n.scriptMessage("custom error: 你好", language: "en"), "custom error: 你好")
    }

    func testWorkerUsesRequestedLanguageWithoutChangingTextOrOffsets() async throws {
        let executable = Catalog.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("OhMyBoop")
        let source = "{\n  \"名称\": \"你好，世界😀\"，\n  \"n\": 1\n}"
        var results: [ScriptResult] = []
        for language in ["en", "zh-Hans"] {
            let result = try await ScriptEngine.run(ScriptRequest(toolID: "FormatJSON", text: source, selectionLocation: 0, selectionLength: 0, language: language), executableURL: executable)
            XCTAssertEqual(result.text, source)
            XCTAssertEqual(result.errorOffset, (source as NSString).range(of: "，\n").location)
            results.append(result)
        }
        XCTAssertTrue(results[0].error?.contains("Chinese comma") == true)
        XCTAssertTrue(results[1].error?.contains("中文逗号") == true)
        let valid = "{\"名称\":\"你好，世界\"}"
        let result = try await ScriptEngine.run(ScriptRequest(toolID: "FormatJSON", text: valid, selectionLocation: 0, selectionLength: 0, language: "en"), executableURL: executable)
        XCTAssertNil(result.error)
        XCTAssertTrue(result.text.contains("你好，世界"))
    }

    @MainActor func testCaptureLocalizedUI() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace(storage: DraftStorage(url: folder.appendingPathComponent("draft.json")))
        let session = workspace.session(for: "json")
        session.replaceText("{\n  \"name\": \"你好，世界\",\n  \"count\": 42\n}")
        let hosting = NSHostingView(rootView: ContentView(workspace: workspace).environment(\.locale, L10n.locale))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 740)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/ohmyboop-localized-\(L10n.language).png"))
    }
}
