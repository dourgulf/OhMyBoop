// Created by lidawen.
import Foundation

struct Draft: Codable, Equatable {
    var text = ""
    var selectionLocation = 0
    var selectionLength = 0
    var scrollY: Double = 0
    var highlightLanguage: String? = nil
    var lastActionID: String? = nil
}

struct ArchivedDraft: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    let sourceID: String
    let draft: Draft
}

struct WorkspaceSnapshot: Codable {
    var version = 2
    var selectedID: String? = "json"
    var favorites: Set<String> = ["FormatJSON", "Base64Decode", "JWTDecode", "URLEncode"]
    var drafts: [String: Draft] = [:]
    // Optional for decoding v1, which did not have an archive field.
    var archivedDrafts: [String: [ArchivedDraft]]? = [:]

    func migrated() -> WorkspaceSnapshot {
        guard version == 1 else { return self }
        var next = WorkspaceSnapshot(selectedID: selectedID.map { FormatCatalog.home(for: $0) } ?? "json", favorites: favorites)
        let grouped = Dictionary(grouping: drafts.keys.sorted(), by: { FormatCatalog.home(for: $0) })
        for (formatID, ids) in grouped {
            let primary = FormatCatalog.format(formatID)?.primaryIDs.first
            let active = ids.first { $0 == selectedID }
                ?? ids.first { $0 == primary && !(drafts[$0]?.text.isEmpty ?? true) }
                ?? ids.first { !(drafts[$0]?.text.isEmpty ?? true) }
                ?? ids[0]
            var draft = drafts[active]!
            draft.lastActionID = FormatCatalog.action(active)?.id
            // Legacy automatic mode depended on the tool. Adopt the format's language now.
            if draft.highlightLanguage == nil || draft.highlightLanguage == "automatic" {
                draft.highlightLanguage = FormatCatalog.format(formatID)?.language.rawValue
            }
            next.drafts[formatID] = draft
            // Archive every original, including the active one, without losing source identity.
            next.archivedDrafts?[formatID] = ids.map { ArchivedDraft(id: "v1/" + $0, sourceID: $0, draft: drafts[$0]!) }
        }
        return next
    }
}

struct DraftStorage {
    let url: URL
    var legacyURL: URL? = nil
    static var applicationDefault: DraftStorage {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DraftStorage(url: root.appendingPathComponent("OhMyBoop/workspace.json"), legacyURL: root.appendingPathComponent("OhMyDevOps/workspace.json"))
    }
    private var sourceURL: URL? {
        if FileManager.default.fileExists(atPath: url.path) { return url }
        if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) { return legacyURL }
        return nil
    }
    func load() throws -> WorkspaceSnapshot {
        guard let sourceURL else { return WorkspaceSnapshot() }
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(contentsOf: sourceURL))
        guard [1, 2].contains(snapshot.version) else { throw EngineError.message("无法读取此版本的草稿文件。") }
        return snapshot
    }
    // Must succeed before the first v2 write. The original file is never overwritten by the backup.
    @discardableResult func backupLegacy() throws -> URL? {
        guard let sourceURL else { return nil }
        let bytes = try Data(contentsOf: sourceURL)
        let backup = sourceURL.appendingPathExtension("v1-backup")
        if FileManager.default.fileExists(atPath: backup.path), try Data(contentsOf: backup) == bytes { return backup }
        let destination = FileManager.default.fileExists(atPath: backup.path)
            ? sourceURL.appendingPathExtension("v1-\(UUID().uuidString).backup") : backup
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return destination
    }
    func save(_ snapshot: WorkspaceSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
