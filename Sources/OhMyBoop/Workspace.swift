// Created by lidawen.
import AppKit
import Observation

struct Draft: Codable, Equatable {
    var text = ""
    var selectionLocation = 0
    var selectionLength = 0
    var scrollY: Double = 0
    var highlightLanguage: String? = nil
}

struct WorkspaceSnapshot: Codable {
    var version = 1
    var selectedID: String? = "FormatJSON"
    var favorites: Set<String> = ["FormatJSON", "Base64Decode", "JWTDecode", "URLEncode"]
    var drafts: [String: Draft] = [:]
}

struct DraftStorage {
    let url: URL
    var legacyURL: URL? = nil
    static var applicationDefault: DraftStorage {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DraftStorage(
            url: root.appendingPathComponent("OhMyBoop/workspace.json"),
            legacyURL: root.appendingPathComponent("OhMyDevOps/workspace.json")
        )
    }
    func load() throws -> WorkspaceSnapshot {
        let source: URL
        if FileManager.default.fileExists(atPath: url.path) {
            source = url
        } else if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
            source = legacyURL
        } else {
            return WorkspaceSnapshot()
        }
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(contentsOf: source))
        guard snapshot.version == 1 else { throw EngineError.message("无法读取此版本的草稿文件。") }
        return snapshot
    }
    func save(_ snapshot: WorkspaceSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor @Observable
final class EditorSession: NSObject, NSTextViewDelegate {
    let id: String
    var text: String
    var message: String?
    var isError = false
    var isRunning = false
    var highlightStatus = "等待输入"
    var highlightLanguage: HighlightLanguage {
        didSet {
            initialDraft.highlightLanguage = highlightLanguage.rawValue
            (backingScroll?.documentView as? HighlightTextView)?.language = highlightLanguage
            onChange?()
        }
    }
    var characterCount: Int { text.count }
    var lineCount: Int { text.components(separatedBy: "\n").count }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var initialDraft: Draft
    @ObservationIgnored private var backingScroll: NSScrollView?
    @ObservationIgnored private var scrollObserver: NSObjectProtocol?
    @ObservationIgnored private let history = UndoManager()

    init(id: String, draft: Draft) {
        self.id = id
        text = draft.text
        initialDraft = draft
        highlightLanguage = HighlightLanguage(rawValue: draft.highlightLanguage ?? "automatic") ?? .automatic
        super.init()
    }

    var scrollView: NSScrollView {
        if let backingScroll { return backingScroll }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let editor = HighlightTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.allowsUndo = true
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 24, height: 24)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.string = text
        editor.setAccessibilityLabel("\(id) 文本编辑器")
        editor.delegate = self
        let count = (text as NSString).length
        let start = min(max(0, initialDraft.selectionLocation), count)
        editor.setSelectedRange(NSRange(location: start, length: min(max(0, initialDraft.selectionLength), count - start)))
        scroll.documentView = editor
        backingScroll = scroll
        editor.onHighlight = { [weak self] status in self?.highlightStatus = status }
        editor.automaticHint = HighlightLanguage.hint(for: id)
        editor.language = highlightLanguage
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        return scroll
    }

    func restoreScroll() {
        guard let scroll = backingScroll else { return }
        scroll.layoutSubtreeIfNeeded()
        if let editor = scroll.documentView as? NSTextView, let container = editor.textContainer {
            editor.layoutManager?.ensureLayout(for: container)
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: initialDraft.scrollY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func captureScroll() { initialDraft = snapshot() }

    func snapshot() -> Draft {
        guard let scroll = backingScroll, let editor = scroll.documentView as? NSTextView else { return initialDraft }
        let range = editor.selectedRange()
        return Draft(text: editor.string, selectionLocation: range.location, selectionLength: range.length, scrollY: scroll.contentView.bounds.origin.y, highlightLanguage: highlightLanguage.rawValue)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { history }
    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView else { return }
        text = editor.string
        message = nil
        onChange?()
    }
    func textViewDidChangeSelection(_ notification: Notification) { onChange?() }

    func replaceText(_ value: String, selection: NSRange? = nil) {
        guard let editor = scrollView.documentView as? NSTextView else { return }
        let previousText = editor.string
        let previousSelection = editor.selectedRange()
        guard previousText != value else { return }
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        editor.breakUndoCoalescing()
        history.registerUndo(withTarget: self) { target in
            target.replaceText(previousText, selection: previousSelection)
        }
        editor.textStorage?.replaceCharacters(in: range, with: value)
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textColor = .textColor
        editor.didChangeText()
        text = value
        message = nil
        onChange?()
        if let selection {
            let count = (value as NSString).length
            let location = min(selection.location, count)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, count - location)))
        }
        editor.breakUndoCoalescing()
    }

    func run() {
        guard !isRunning else { return }
        let draft = snapshot()
        isRunning = true
        message = nil
        (scrollView.documentView as? NSTextView)?.isEditable = false
        Task {
            defer {
                isRunning = false
                (scrollView.documentView as? NSTextView)?.isEditable = true
            }
            do {
                let result = try await ScriptEngine.run(ScriptRequest(toolID: id, text: draft.text, selectionLocation: draft.selectionLocation, selectionLength: draft.selectionLength))
                if result.error == nil, result.text != text {
                    replaceText(result.text, selection: NSRange(location: result.selectionLocation, length: result.selectionLength))

                }
                isError = result.error != nil
                message = result.error ?? result.info ?? "处理完成"
            } catch {
                isError = true
                message = error.localizedDescription
            }
        }
    }
}

@MainActor @Observable
final class Workspace {
    var tools: [Tool] = []
    var selectedID: String? { didSet { scheduleSave() } }
    var favorites: Set<String> = []
    var storageMessage: String?
    @ObservationIgnored private var drafts: [String: Draft] = [:]
    @ObservationIgnored private var sessions: [String: EditorSession] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let storage: DraftStorage
    @ObservationIgnored private var canSave = true

    init(storage: DraftStorage = .applicationDefault) {
        self.storage = storage
        do {
            tools = try Catalog.load()
            let snapshot = try storage.load()
            selectedID = tools.contains(where: { $0.id == snapshot.selectedID }) ? snapshot.selectedID : tools.first?.id
            favorites = snapshot.favorites
            drafts = snapshot.drafts
        } catch {
            selectedID = tools.first?.id
            storageMessage = "读取失败：\(error.localizedDescription) 原文件已保留，本次不覆盖草稿。"
            canSave = false
        }
    }

    func session(for id: String) -> EditorSession {
        if let session = sessions[id] { return session }
        let session = EditorSession(id: id, draft: drafts[id] ?? Draft())
        session.onChange = { [weak self] in self?.scheduleSave() }
        sessions[id] = session
        return session
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        scheduleSave()
    }
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
    func save() {
        guard canSave else { return }
        for (id, session) in sessions { drafts[id] = session.snapshot() }
        do {
            try storage.save(WorkspaceSnapshot(selectedID: selectedID, favorites: favorites, drafts: drafts))
            storageMessage = nil
        } catch { storageMessage = "草稿保存失败：\(error.localizedDescription)" }
    }
}
