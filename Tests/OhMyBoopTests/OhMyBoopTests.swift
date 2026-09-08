import XCTest
import AppKit
import SwiftUI
@testable import OhMyBoop

final class ScriptEngineTests: XCTestCase {
    private func run(_ id: String, _ text: String, location: Int = 0, length: Int = 0) throws -> ScriptResult {
        try ScriptEngine.execute(ScriptRequest(toolID: id, text: text, selectionLocation: location, selectionLength: length))
    }

    func testCatalogLoadsAllLocalBoopTools() throws {
        let tools = try Catalog.load()
        XCTAssertEqual(tools.count, 72)
        XCTAssertEqual(Set(tools.map(\.id)).count, tools.count)
    }

    func testJSONFormattingAndInvalidInputIsPreserved() throws {
        XCTAssertEqual(try run("FormatJSON", "{\"a\":1}").text, "{\n  \"a\": 1\n}")
        let invalid = try run("FormatJSON", "{bad json}")
        XCTAssertNotNil(invalid.error)
        XCTAssertEqual(invalid.text, "{bad json}")
    }

    func testSelectedTextUsesUTF16AndPreservesSurroundings() throws {
        let result = try run("Upcase", "😀 hello world", location: 3, length: 5)
        XCTAssertEqual(result.text, "😀 HELLO world")
        XCTAssertEqual(result.selectionLocation, 3)
        XCTAssertEqual(result.selectionLength, 5)
    }

    func testAllSevenBundledLibraries() throws {
        let encoded = try run("Base64Encode", "你好 🌍").text
        XCTAssertEqual(try run("Base64Decode", encoded).text, "你好 🌍")
        XCTAssertEqual(try run("SHA256", "abc").text, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try run("CamelCase", "hello world").text, "helloWorld")
        XCTAssertEqual(try run("HTMLDecode", "&lt;b&gt;&amp;").text, "<b>&")
        let yaml = try run("JSONtoYAML", "{\"name\":\"Ada\"}")
        XCTAssertNil(yaml.error)
        XCTAssertTrue(yaml.text.contains("name: Ada"))
        XCTAssertTrue(try run("YAMLtoJSON", yaml.text).text.contains("\"Ada\""))
        XCTAssertTrue(try run("CSVtoJSON", "name,age\nAda,30").text.contains("\"Ada\""))
        XCTAssertTrue(try run("FormatSQL", "select * from users where id=1").text.contains("\n"))
    }

    func testInformationalToolsDoNotReplaceInput() throws {
        let result = try run("CountWords", "one two three")
        XCTAssertEqual(result.info, "3 words")
        XCTAssertEqual(result.text, "one two three")
    }

    func testErrorsCannotPartiallyMutateDraft() throws {
        let input = "throw new Error('test')"
        let result = try run("EvalJavascript", input)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.text, input)
    }

    func testAll72ToolsExecuteWithRepresentativeInput() throws {
        let samples: [String: String] = [
            "Base64Decode": "aGVsbG8=", "BinaryToDecimal": "1010", "CSVtoJSON": "name,age\nAda,30",
            "DateToTimestamp": "2026-09-08T00:00:00Z", "DateToUTC": "2026-09-08T00:00:00Z",
            "DecimalToBinary": "42", "DecimalToHex": "255", "EvalJavascript": "1 + 2",
            "FormatCSS": "body{color:red;}", "FormatJSON": "{\"a\":1}", "FormatSQL": "select * from users",
            "FormatXML": "<root><item>1</item></root>", "HexToASCII": "68656C6C6F", "HexToDecimal": "ff",
            "IOSAndroidStrings": "\"hello\" = \"Hello\";", "AndroidIOSStrings": "<string name=\"hello\">Hello</string>",
            "JSONtoCSV": "[{\"a\":1}]", "JSONtoYAML": "{\"a\":1}", "JsonToQuery": "{\"a\":1}",
            "JWTDecode": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature",
            "MinifyCSS": "body { color: red; }", "MinifyJSON": "{\"a\": 1}", "MinifySQL": "select * from users",
            "MinifyXML": "<root> <item>1</item> </root>", "PhpUnserialize": "a:1:{s:1:\"a\";i:1;}",
            "QueryToJson": "a=1&b=two", "SortJSON": "{\"b\":2,\"a\":1}", "SumAll": "1\n2\n3",
            "YAMLtoJSON": "name: Ada", "hex2rgb": "#ff0088"
        ]
        for tool in try Catalog.load() {
            let result = try run(tool.id, samples[tool.id] ?? "hello world\nsecond line")
            XCTAssertNil(result.error, "\(tool.id): \(result.error ?? "")")
        }
    }

    func testRealWorkerProcessAndInfiniteScriptTimeout() async throws {
        let executable = Catalog.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("OhMyBoop")
        let request = ScriptRequest(toolID: "FormatJSON", text: "{\"ok\":true}", selectionLocation: 0, selectionLength: 0)
        let result = try await ScriptEngine.run(request, executableURL: executable)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.text, "{\n  \"ok\": true\n}")
        do {
            _ = try await ScriptEngine.run(ScriptRequest(toolID: "EvalJavascript", text: "while(true) {}", selectionLocation: 0, selectionLength: 0), timeout: 1, executableURL: executable)
            XCTFail("An infinite script must time out")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("已停止"), error.localizedDescription)
        }
    }
}

final class PersistenceTests: XCTestCase {
    func testRenameRestoresLegacyDraftWithoutOverwritingEitherFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = DraftStorage(url: folder.appendingPathComponent("old/workspace.json"))
        let oldSnapshot = WorkspaceSnapshot(selectedID: "Base64Encode", favorites: ["Base64Encode"], drafts: ["Base64Encode": Draft(text: "retained input", selectionLocation: 2, selectionLength: 3, scrollY: 120)])
        try legacy.save(oldSnapshot)
        let originalBytes = try Data(contentsOf: legacy.url)
        let renamed = DraftStorage(url: folder.appendingPathComponent("new/workspace.json"), legacyURL: legacy.url)
        let migrated = try renamed.load()
        XCTAssertEqual(migrated.drafts, oldSnapshot.drafts)
        XCTAssertEqual(migrated.selectedID, oldSnapshot.selectedID)
        XCTAssertEqual(migrated.favorites, oldSnapshot.favorites)
        try renamed.save(migrated)
        XCTAssertEqual(try Data(contentsOf: legacy.url), originalBytes)
        var newer = migrated
        newer.drafts["Base64Encode"] = Draft(text: "new input")
        try renamed.save(newer)
        XCTAssertEqual(try renamed.load().drafts["Base64Encode"]?.text, "new input")
    }

    @MainActor func testRenderWorkspacePreview() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace(storage: DraftStorage(url: folder.appendingPathComponent("workspace.json")))
        workspace.session(for: "FormatJSON").replaceText("{\n  \"app\": \"OhMyBoop\",\n  \"layout\": \"sidebar + editor\",\n  \"features\": [\n    \"72 local tools\",\n    \"independent drafts\",\n    \"restore on restart\"\n  ],\n  \"ready\": true\n}")
        let hosting = NSHostingView(rootView: ContentView(workspace: workspace))
        hosting.frame = NSRect(x: 0, y: 0, width: 1120, height: 740)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/ohmyboop-preview.png"))
        window.orderOut(nil)
    }

    func testIndependentDraftsSelectionScrollAndFavoritesRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = DraftStorage(url: folder.appendingPathComponent("workspace.json"))
        let first = Draft(text: "JSON draft", selectionLocation: 2, selectionLength: 4, scrollY: 240)
        let second = Draft(text: "Base64 draft")
        try storage.save(WorkspaceSnapshot(selectedID: "Base64Encode", favorites: ["FormatJSON"], drafts: ["FormatJSON": first, "Base64Encode": second]))
        let restored = try storage.load()
        XCTAssertEqual(restored.drafts["FormatJSON"], first)
        XCTAssertEqual(restored.drafts["Base64Encode"], second)
        XCTAssertEqual(restored.selectedID, "Base64Encode")
        XCTAssertEqual(restored.favorites, ["FormatJSON"])
    }

    @MainActor func testSessionSwitchingRetainsTextSelectionAndIsolatedUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = DraftStorage(url: folder.appendingPathComponent("workspace.json"))
        let workspace = Workspace(storage: storage)
        let first = workspace.session(for: "FormatJSON")
        let second = workspace.session(for: "Base64Encode")
        first.replaceText("one", selection: NSRange(location: 1, length: 1))
        second.replaceText("two")
        XCTAssertTrue(first === workspace.session(for: "FormatJSON"))
        XCTAssertEqual(first.snapshot().text, "one")
        XCTAssertEqual(first.snapshot().selectionLocation, 1)
        XCTAssertEqual(second.snapshot().text, "two")
        let editor = first.scrollView.documentView as! NSTextView
        first.undoManager(for: editor)?.undo()
        XCTAssertEqual(first.text, "")
        XCTAssertEqual(second.text, "two")
        workspace.save()
        let reopened = Workspace(storage: storage)
        XCTAssertEqual(reopened.session(for: "Base64Encode").text, "two")
    }

    @MainActor func testCorruptDraftIsNeverOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storage = DraftStorage(url: folder.appendingPathComponent("workspace.json"))
        let original = Data("broken json".utf8)
        try original.write(to: storage.url)
        let workspace = Workspace(storage: storage)
        workspace.save()
        XCTAssertNotNil(workspace.storageMessage)
        XCTAssertEqual(try Data(contentsOf: storage.url), original)
    }
}
