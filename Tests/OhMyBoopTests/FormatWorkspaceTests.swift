import XCTest
import AppKit
import SwiftUI
@testable import OhMyBoop

final class FormatWorkspaceTests: XCTestCase {
    private var executable: URL {
        Catalog.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("OhMyBoop")
    }
    private func action(_ id: String) throws -> ToolAction { try XCTUnwrap(FormatCatalog.action(id)) }

    func testEveryScriptHasAnExplicitReachableAction() throws {
        let tools = try Catalog.load()
        XCTAssertEqual(Set(FormatCatalog.actions.map(\.id)), Set(tools.map(\.id)))
        XCTAssertEqual(FormatCatalog.actions.count, tools.count)
        for format in FormatCatalog.formats {
            XCTAssertFalse(format.primaryActions.isEmpty, format.id)
            XCTAssertEqual(format.primaryActions.count, format.primaryIDs.count)
            XCTAssertEqual(Set(format.actions.map(\.id)).count, format.actions.count)
        }
        for action in FormatCatalog.actions {
            XCTAssertTrue(FormatCatalog.format(action.home)?.actions.contains(action) == true, action.id)
        }
        XCTAssertEqual(try action("SortJSON").title, "排序（含数组）")
        XCTAssertEqual(FormatCatalog.format("css")?.language, .plaintext)
    }

    @MainActor func testSearchRevealsActionWithoutRunningOrChangingDraft() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace(storage: DraftStorage(url: folder.appendingPathComponent("state.json")))
        let session = workspace.session(for: "json")
        session.replaceText("{\\\"a\\\":1}")
        let before = session.snapshot()
        let matches = FormatCatalog.search("去反斜杠", tools: workspace.tools)
        let match = try XCTUnwrap(matches.first { $0.format.id == "json" })
        workspace.reveal(match)
        XCTAssertEqual(workspace.selectedID, "json")
        XCTAssertEqual(workspace.revealedActionID, "RemoveSlashes")
        XCTAssertEqual(session.snapshot(), before)
        XCTAssertFalse(session.isRunning)
        XCTAssertTrue(workspace.session(for: "FormatJSON") === workspace.session(for: "MinifyJSON"))
        XCTAssertFalse(workspace.session(for: "yaml") === session)
    }

    @MainActor func testLegacyMigrationBacksUpExactBytesAndKeepsEverySourceDraft() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = DraftStorage(url: folder.appendingPathComponent("state.json"))
        let legacy = WorkspaceSnapshot(version: 1, selectedID: "MinifyJSON", favorites: ["SortJSON"], drafts: [
            "FormatJSON": Draft(text: "formatted", selectionLocation: 1, selectionLength: 2, scrollY: 90),
            "MinifyJSON": Draft(text: "compressed", selectionLocation: 3, selectionLength: 1),
            "SortJSON": Draft(text: "sorted"), "YAMLtoJSON": Draft(text: "name: yaml"),
            "RetiredTool": Draft(text: "unknown but recoverable")
        ])
        try storage.save(legacy)
        let bytes = try Data(contentsOf: storage.url)
        let workspace = Workspace(storage: storage)
        XCTAssertNil(workspace.storageMessage)
        XCTAssertEqual(workspace.selectedID, "json")
        XCTAssertEqual(workspace.session(for: "json").text, "compressed")
        XCTAssertEqual(workspace.session(for: "json").snapshot().selectionLocation, 3)
        XCTAssertEqual(workspace.favorites, ["SortJSON"])
        XCTAssertEqual(try Data(contentsOf: storage.url.appendingPathExtension("v1-backup")), bytes)
        XCTAssertEqual(try storage.load().version, 2)
        let archives = workspace.archivedDrafts.values.flatMap { $0 }
        XCTAssertEqual(archives.count, legacy.drafts.count)
        for archive in archives { XCTAssertEqual(archive.draft, legacy.drafts[archive.sourceID]) }
        workspace.session(for: "json").replaceText("new working content")
        let archived = try XCTUnwrap(workspace.archivedDrafts["json"]?.first { $0.sourceID == "FormatJSON" })
        workspace.restoreArchive(archived, in: "json")
        XCTAssertEqual(workspace.session(for: "json").text, "formatted")
        XCTAssertTrue(workspace.archivedDrafts["json"]!.contains { $0.draft.text == "new working content" })
        XCTAssertEqual(workspace.archivedDrafts["json"]?.count, 4)
        workspace.save()
        let reopened = Workspace(storage: storage)
        XCTAssertEqual(reopened.archivedDrafts["json"]?.count, 4)
        XCTAssertEqual(reopened.session(for: "json").text, "formatted")
        XCTAssertEqual(try Data(contentsOf: storage.url.appendingPathExtension("v1-backup")), bytes)
    }

    func testMigrationUsesPrimaryThenStableNonemptyFallback() {
        let snapshot = WorkspaceSnapshot(version: 1, selectedID: "YAMLtoJSON", drafts: [
            "FormatJSON": Draft(text: "primary"), "SortJSON": Draft(text: "other"), "MinifyJSON": Draft(text: "")
        ])
        XCTAssertEqual(snapshot.migrated().drafts["json"]?.text, "primary")
        var fallback = snapshot
        fallback.drafts["FormatJSON"] = Draft()
        XCTAssertEqual(fallback.migrated().drafts["json"]?.text, "other")
    }

    @MainActor func testBackupFailureKeepsRecoveredDraftAndDisablesWrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = DraftStorage(url: folder.appendingPathComponent("state.json"))
        try storage.save(WorkspaceSnapshot(version: 1, selectedID: "FormatJSON", drafts: ["FormatJSON": Draft(text: "keep me")]))
        let original = try Data(contentsOf: storage.url)
        try FileManager.default.createDirectory(at: storage.url.appendingPathExtension("v1-backup"), withIntermediateDirectories: true)
        let workspace = Workspace(storage: storage)
        XCTAssertNotNil(workspace.storageMessage)
        XCTAssertEqual(workspace.session(for: "json").text, "keep me")
        workspace.session(for: "json").replaceText("do not overwrite")
        workspace.save()
        XCTAssertEqual(try Data(contentsOf: storage.url), original)
    }

    @MainActor func testSequentialActionsHaveSeparateUndoSteps() async throws {
        let source = "{\\\"b\\\":2,\\\"a\\\":1}"
        let session = EditorSession(id: "json", draft: Draft(text: source))
        await session.perform(try action("RemoveSlashes"), executableURL: executable)
        let unescaped = session.text
        XCTAssertEqual(unescaped, "{\"b\":2,\"a\":1}")
        await session.perform(try action("FormatJSON"), executableURL: executable)
        let formatted = session.text
        XCTAssertTrue(formatted.contains("\n"))
        await session.perform(try action("MinifyJSON"), executableURL: executable)
        XCTAssertEqual(session.text, unescaped)
        let editor = session.scrollView.documentView as! NSTextView
        let undo = try XCTUnwrap(session.undoManager(for: editor))
        undo.undo(); XCTAssertEqual(session.text, formatted)
        undo.undo(); XCTAssertEqual(session.text, unescaped)
        undo.undo(); XCTAssertEqual(session.text, source)
        undo.redo(); XCTAssertEqual(session.text, unescaped)
        XCTAssertEqual(session.lastAction?.id, "MinifyJSON")
    }

    @MainActor func testConversionPreviewExtractsSelectionAndLeavesBothDraftsUntouched() async throws {
        let source = "🌍 before {\"name\":\"Ada\"} after"
        let range = (source as NSString).range(of: "{\"name\":\"Ada\"}")
        let session = EditorSession(id: "json", draft: Draft(text: source, selectionLocation: range.location, selectionLength: range.length))
        let yaml = EditorSession(id: "yaml", draft: Draft(text: "existing: draft"))
        let before = session.snapshot()
        await session.perform(try action("JSONtoYAML"), executableURL: executable)
        XCTAssertFalse(session.isError, session.message ?? "")
        XCTAssertEqual(session.text, before.text)
        XCTAssertEqual(session.snapshot().selectionLocation, before.selectionLocation)
        XCTAssertEqual(session.snapshot().selectionLength, before.selectionLength)
        XCTAssertEqual(yaml.text, "existing: draft")
        let preview = try XCTUnwrap(session.preview)
        XCTAssertEqual(preview.text.trimmingCharacters(in: .whitespacesAndNewlines), "name: Ada")
        XCTAssertEqual(preview.highlightLanguage, .yaml)
        XCTAssertFalse((preview.scrollView.documentView as! NSTextView).isEditable)
        session.replaceText("{bad json}")
        XCTAssertNil(session.preview)
        await session.perform(try action("JSONtoYAML"), executableURL: executable)
        XCTAssertTrue(session.isError)
        XCTAssertNil(session.preview)
        XCTAssertEqual(session.text, "{bad json}")
    }

    @MainActor func testWholeDocumentAndInformationalActionsPreserveTheirContracts() async throws {
        let number = EditorSession(id: "number", draft: Draft(text: "ab", selectionLocation: 0, selectionLength: 1))
        await number.perform(try action("ASCIIToHex"), executableURL: executable)
        XCTAssertEqual(number.text, "ab")
        XCTAssertEqual(number.preview?.text.lowercased(), "6162")
        XCTAssertEqual(number.scope(for: try action("ASCIIToHex")), L10n.text("处理全文"))
        let text = EditorSession(id: "text", draft: Draft(text: "hello world"))
        await text.perform(try action("CountWords"), executableURL: executable)
        XCTAssertEqual(text.text, "hello world")
        XCTAssertEqual(text.message, L10n.text("词数：%@", "2"))
        XCTAssertNil(text.preview)
        let hash = EditorSession(id: "hash", draft: Draft(text: "abc"))
        await hash.perform(try action("SHA256"), executableURL: executable)
        XCTAssertEqual(hash.text, "abc")
        XCTAssertEqual(hash.preview?.text, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @MainActor func testRunningSessionRejectsSecondAction() async throws {
        let session = EditorSession(id: "json", draft: Draft(text: "{\"a\":1}"))
        let format = try action("FormatJSON")
        let worker = executable
        let first = Task { await session.perform(format, executableURL: worker) }
        let deadline = Date().addingTimeInterval(5)
        while !session.isRunning && Date() < deadline { await Task.yield() }
        XCTAssertTrue(session.isRunning)
        XCTAssertFalse((session.scrollView.documentView as! NSTextView).isEditable)
        await session.perform(try action("MinifyJSON"), executableURL: worker)
        await first.value
        XCTAssertEqual(session.lastAction?.id, "FormatJSON")
        XCTAssertTrue(session.text.contains("\n"))
        XCTAssertTrue((session.scrollView.documentView as! NSTextView).isEditable)
    }

    @MainActor func testRestoreSameTextRestoresSelectionAndClampsOldRanges() {
        let session = EditorSession(id: "json", draft: Draft(text: "{\"a\":1}"))
        _ = session.scrollView
        session.restore(Draft(text: "{\"a\":1}", selectionLocation: 2, selectionLength: 2))
        XCTAssertEqual(session.snapshot().selectionLocation, 2)
        XCTAssertEqual(session.snapshot().selectionLength, 2)
        session.restore(Draft(text: "changed", selectionLocation: -20, selectionLength: 200))
        XCTAssertEqual(session.snapshot().selectionLocation, 0)
        XCTAssertEqual(session.snapshot().selectionLength, 7)
    }

    @MainActor func testResultViewReplacementAndLightDarkLayouts() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        for dark in [false, true] {
            let workspace = Workspace(storage: DraftStorage(url: folder.appendingPathComponent(UUID().uuidString)))
            let session = workspace.session(for: "json")
            session.replaceText("[{\"name\":\"Ada\",\"tools\":72},{\"name\":\"你好 🌍\",\"tools\":3}]")
            await session.perform(try action("JSONtoYAML"), executableURL: executable)
            let first = try XCTUnwrap(session.preview)
            let hosting = NSHostingView(rootView: ContentView(workspace: workspace).environment(\.colorScheme, dark ? .dark : .light))
            hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = NSSize(width: dark ? 800 : 1120, height: 740)
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            XCTAssertNotNil(first.scrollView.superview)
            await session.perform(try action("JSONtoCSV"), executableURL: executable)
            let second = try XCTUnwrap(session.preview)
            XCTAssertFalse(first === second)
            hosting.layoutSubtreeIfNeeded()
            let deadline = Date().addingTimeInterval(5)
            while second.scrollView.superview == nil && Date() < deadline {
                try await Task.sleep(for: .milliseconds(25))
                hosting.layoutSubtreeIfNeeded()
            }
            XCTAssertNotNil(second.scrollView.superview)
            XCTAssertNil(first.scrollView.superview)
            XCTAssertEqual(second.highlightLanguage, .plaintext)
            // Capture the YAML result so both panes exercise independent highlighting.
            await session.perform(try action("JSONtoYAML"), executableURL: executable)
            hosting.layoutSubtreeIfNeeded()
            let preview = try XCTUnwrap(session.preview)
            let editors = [session.scrollView.documentView, preview.scrollView.documentView].compactMap { $0 as? HighlightTextView }
            let highlightDeadline = Date().addingTimeInterval(5)
            while editors.contains(where: { $0.lastAppliedGeneration == 0 }) && Date() < highlightDeadline {
                try await Task.sleep(for: .milliseconds(25))
                hosting.layoutSubtreeIfNeeded()
            }
            XCTAssertTrue(editors.allSatisfy { $0.lastAppliedGeneration > 0 })
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/ohmyboop-format-result-\(dark ? "dark" : "light").png"))
        }
    }
}
