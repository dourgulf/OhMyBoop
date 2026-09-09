// Created by lidawen.
import AppKit
import Observation

@MainActor @Observable
final class EditorSession: NSObject, NSTextViewDelegate {
    let id: String
    let isReadOnly: Bool
    var preview: EditorSession?
    var previewTitle: String?
    var selectionLength = 0
    var lastActionID: String? { didSet { initialDraft.lastActionID = lastActionID; onChange?() } }
    var text: String
    var message: String?
    var isError = false
    var isRunning = false
    var highlightStatus = L10n.text("等待输入")
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
    @ObservationIgnored private var fontObserver: NSObjectProtocol?
    @ObservationIgnored private let preferences: EditorPreferences
    @ObservationIgnored private let history = UndoManager()

    init(id: String, draft: Draft, defaultLanguage: HighlightLanguage? = nil, isReadOnly: Bool = false, preferences: EditorPreferences? = nil) {
        self.id = id
        self.isReadOnly = isReadOnly
        self.preferences = preferences ?? .shared
        selectionLength = draft.selectionLength
        lastActionID = draft.lastActionID
        text = draft.text
        initialDraft = draft
        highlightLanguage = draft.highlightLanguage.flatMap(HighlightLanguage.init(rawValue:)) ?? defaultLanguage ?? FormatCatalog.format(FormatCatalog.home(for: id))?.language ?? .plaintext
        super.init()
        fontObserver = NotificationCenter.default.addObserver(forName: EditorPreferences.changed, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let source = notification.object as? EditorPreferences, source === self.preferences else { return }
                self.applyEditorFont()
            }
        }
    }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        if let fontObserver { NotificationCenter.default.removeObserver(fontObserver) }
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
        editor.allowsUndo = !isReadOnly
        editor.isEditable = !isReadOnly
        editor.font = preferences.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = ("  " as NSString).size(withAttributes: [.font: editor.font!]).width
        editor.defaultParagraphStyle = paragraph
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
        editor.setAccessibilityLabel(L10n.text("%@ 文本编辑器", id))
        editor.delegate = self
        let count = (text as NSString).length
        let start = min(max(0, initialDraft.selectionLocation), count)
        editor.setSelectedRange(NSRange(location: start, length: min(max(0, initialDraft.selectionLength), count - start)))
        scroll.documentView = editor
        scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, editor: editor)
        scroll.hasVerticalRuler = true
        scroll.hasHorizontalRuler = false
        scroll.rulersVisible = true
        backingScroll = scroll
        editor.onHighlight = { [weak self] status in self?.highlightStatus = status }
        editor.automaticHint = format?.language == .plaintext ? nil : format?.language.rawValue
        editor.language = highlightLanguage
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                (self?.backingScroll?.documentView as? HighlightTextView)?.scheduleViewportHighlight()
                self?.onChange?()
            }
        }
        return scroll
    }

    private func applyEditorFont() {
        guard let scroll = backingScroll, let editor = scroll.documentView as? HighlightTextView else { return }
        let selection = editor.selectedRange()
        let scrollY = scroll.contentView.bounds.minY
        let font = preferences.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = ("  " as NSString).size(withAttributes: [.font: font]).width
        editor.font = font
        editor.defaultParagraphStyle = paragraph
        editor.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.typingAttributes[.font] = font
        editor.typingAttributes[.paragraphStyle] = paragraph
        (scroll.verticalRulerView as? LineNumberRuler)?.updateLineStarts()
        if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
        editor.setSelectedRange(selection)
        scroll.contentView.scroll(to: NSPoint(x: -scroll.contentView.contentInsets.left, y: scrollY))
        editor.needsDisplay = true
        editor.scheduleHighlight()
    }

    func restoreScroll() {
        guard let scroll = backingScroll else { return }
        scroll.layoutSubtreeIfNeeded()
        if let editor = scroll.documentView as? NSTextView, let container = editor.textContainer {
            editor.layoutManager?.ensureLayout(for: container)
        }
        // NSScrollView reserves ruler space through the clip view's content inset.
        scroll.contentView.scroll(to: NSPoint(x: -scroll.contentView.contentInsets.left, y: initialDraft.scrollY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func captureScroll() { initialDraft = snapshot() }

    func snapshot() -> Draft {
        guard let scroll = backingScroll, let editor = scroll.documentView as? NSTextView else { return initialDraft }
        let range = editor.selectedRange()
        return Draft(text: editor.string, selectionLocation: range.location, selectionLength: range.length, scrollY: scroll.contentView.bounds.origin.y, highlightLanguage: highlightLanguage.rawValue, lastActionID: lastActionID)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { history }
    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView else { return }
        text = editor.string
        message = nil
        isError = false
        (editor as? HighlightTextView)?.showError(at: nil)
        closePreview()
        onChange?()
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        selectionLength = (notification.object as? NSTextView)?.selectedRange().length ?? 0
        onChange?()
    }

    func replaceText(_ value: String, selection: NSRange? = nil) {
        guard let editor = scrollView.documentView as? NSTextView else { return }
        let previousText = editor.string
        let previousSelection = editor.selectedRange()
        guard previousText != value else { return }
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        editor.breakUndoCoalescing()
        history.beginUndoGrouping()
        history.registerUndo(withTarget: self) { target in
            target.replaceText(previousText, selection: previousSelection)
        }
        history.endUndoGrouping()
        editor.textStorage?.replaceCharacters(in: range, with: value)
        editor.font = preferences.font
        editor.textColor = .textColor
        editor.didChangeText()
        text = value
        message = nil
        onChange?()
        if let selection {
            let count = (value as NSString).length
            let location = min(max(0, selection.location), count)
            editor.setSelectedRange(NSRange(location: location, length: min(max(0, selection.length), count - location)))
        }
        editor.breakUndoCoalescing()
    }

    var format: ContentFormat? { FormatCatalog.format(FormatCatalog.home(for: id)) }
    var lastAction: ToolAction? {
        format?.actions.first { $0.id == lastActionID } ?? format?.primaryActions.first
    }
    func scope(for action: ToolAction?) -> String {
        action?.wholeDocument == true || selectionLength == 0 ? L10n.text("处理全文") : L10n.text("处理选区 · %@ 字符", String(selectionLength))
    }
    func closePreview() { preview = nil; previewTitle = nil }

    func restore(_ draft: Draft) {
        guard !isRunning, !isReadOnly else { return }
        (scrollView.documentView as? HighlightTextView)?.showError(at: nil)
        replaceText(draft.text, selection: NSRange(location: draft.selectionLocation, length: draft.selectionLength))
        if let editor = scrollView.documentView as? NSTextView {
            let count = (editor.string as NSString).length
            let location = min(max(0, draft.selectionLocation), count)
            editor.setSelectedRange(NSRange(location: location, length: min(max(0, draft.selectionLength), count - location)))
        }
        closePreview()
        highlightLanguage = draft.highlightLanguage.flatMap(HighlightLanguage.init(rawValue:)) ?? format?.language ?? .plaintext
        lastActionID = draft.lastActionID
        initialDraft = draft
        message = L10n.text("已恢复历史草稿")
        isError = false
        restoreScroll()
        onChange?()
    }

    func run(_ action: ToolAction) {
        Task { await perform(action) }
    }

    func perform(_ action: ToolAction, executableURL: URL? = Bundle.main.executableURL) async {
        guard !isRunning, !isReadOnly, format?.actions.contains(action) == true else { return }
        let draft = snapshot()
        let location = action.wholeDocument ? 0 : draft.selectionLocation
        let length = action.wholeDocument ? 0 : draft.selectionLength
        isRunning = true
        lastActionID = action.id
        message = nil
        isError = false
        closePreview()
        (scrollView.documentView as? HighlightTextView)?.showError(at: nil)
        (scrollView.documentView as? NSTextView)?.isEditable = false
        defer {
            isRunning = false
            (scrollView.documentView as? NSTextView)?.isEditable = true
        }
        do {
            let result = try await ScriptEngine.run(ScriptRequest(toolID: action.id, text: draft.text, selectionLocation: location, selectionLength: length), executableURL: executableURL)
            guard text == draft.text else {
                message = L10n.text("内容已变化，本次结果未应用。"); return
            }
            guard result.error == nil else {
                isError = true
                message = result.error
                if let offset = result.errorOffset, offset >= 0, offset <= (draft.text as NSString).length {
                    let prefix = (draft.text as NSString).substring(to: offset)
                    // Count visible characters for columns, and treat CRLF as one newline.
                    var line = 1, column = 1
                    for character in prefix {
                        if character == "\n" || character == "\r" || character == "\r\n" {
                            line += 1; column = 1
                        } else { column += 1 }
                    }
                    message = L10n.text("第 %@ 行，第 %@ 列：%@", String(line), String(column), result.error!)
                    if offset == (draft.text as NSString).length { message = L10n.text("%@（文本末尾）", message!) }
                    (scrollView.documentView as? HighlightTextView)?.showError(at: offset)
                }
                return
            }
            switch action.effect {
            case .replace:
                if result.text != text {
                    replaceText(result.text, selection: NSRange(location: result.selectionLocation, length: result.selectionLength))
                }
            case let .preview(outputFormat):
                let output: String
                if length > 0 {
                    let range = NSRange(location: result.selectionLocation, length: result.selectionLength)
                    guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= (result.text as NSString).length else {
                        throw EngineError.message(L10n.text("输出选区无效，原文已保留。"))
                    }
                    output = (result.text as NSString).substring(with: range)
                } else { output = result.text }
                preview = EditorSession(id: "result-" + UUID().uuidString, draft: Draft(text: output), defaultLanguage: FormatCatalog.format(outputFormat)?.language ?? .plaintext, isReadOnly: true, preferences: preferences)
                previewTitle = "\(action.localizedTitle) · \(FormatCatalog.title(outputFormat))"
            case .information: break
            }
            message = result.info ?? (action.outputFormat == nil ? L10n.text("%@完成", action.localizedTitle) : L10n.text("结果已显示，原文保留"))
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }
}

@MainActor @Observable
final class Workspace {
    var tools: [Tool] = []
    var selectedID: String? { didSet { revealedActionID = nil; scheduleSave() } }
    var revealedActionID: String?
    var favorites: Set<String> = []
    var storageMessage: String?
    private(set) var archivedDrafts: [String: [ArchivedDraft]] = [:]
    @ObservationIgnored private var drafts: [String: Draft] = [:]
    @ObservationIgnored private var sessions: [String: EditorSession] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let storage: DraftStorage
    @ObservationIgnored private var canSave = true

    init(storage: DraftStorage = .applicationDefault) {
        self.storage = storage
        do {
            tools = try Catalog.load()
            let loaded = try storage.load()
            let snapshot = loaded.migrated()
            selectedID = FormatCatalog.format(snapshot.selectedID ?? "")?.id ?? "json"
            favorites = snapshot.favorites
            drafts = snapshot.drafts
            archivedDrafts = snapshot.archivedDrafts ?? [:]
            if loaded.version == 1 {
                do {
                    try storage.backupLegacy()
                    try storage.save(snapshot)
                } catch {
                    canSave = false
                    storageMessage = L10n.text("迁移备份或保存失败：%@ 已恢复旧草稿供查看，本次不覆盖文件。", error.localizedDescription)
                }
            }
        } catch {
            selectedID = "json"
            storageMessage = L10n.text("读取失败：%@ 原文件已保留，本次不覆盖草稿。", error.localizedDescription)
            canSave = false
        }
    }

    func session(for id: String) -> EditorSession {
        let formatID = FormatCatalog.home(for: id)
        if let session = sessions[formatID] { return session }
        let session = EditorSession(id: formatID, draft: drafts[formatID] ?? Draft())
        session.onChange = { [weak self] in self?.scheduleSave() }
        sessions[formatID] = session
        return session
    }
    func reveal(_ match: ActionSearchResult) {
        selectedID = match.format.id
        revealedActionID = match.action?.id
    }
    func restoreArchive(_ archive: ArchivedDraft, in formatID: String) {
        let session = session(for: formatID)
        guard !session.isRunning else { return }
        archivedDrafts[formatID, default: []].append(ArchivedDraft(sourceID: "恢复前草稿", draft: session.snapshot()))
        session.restore(archive.draft)
        save()
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
            try storage.save(WorkspaceSnapshot(selectedID: selectedID, favorites: favorites, drafts: drafts, archivedDrafts: archivedDrafts))
            storageMessage = nil
        } catch { storageMessage = L10n.text("草稿保存失败：%@", error.localizedDescription) }
    }
}
