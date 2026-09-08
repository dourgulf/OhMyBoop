// Created by lidawen.
import AppKit
import Highlighter

enum HighlightLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic, plaintext, json, yaml, xml, css, sql, javascript, bash, swift, python, markdown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "自动高亮"
        case .plaintext: "纯文本"
        default: rawValue.uppercased()
        }
    }

    static func hint(for tool: String) -> String? {
        if ["FormatJSON", "MinifyJSON", "SortJSON"].contains(tool) { return "json" }
        if tool.contains("XML") || tool == "AndroidIOSStrings" { return "xml" }
        if tool.contains("SQL") { return "sql" }
        if tool.contains("CSS") { return "css" }
        if tool == "EvalJavascript" { return "javascript" }
        return nil
    }
}

struct HighlightSpan: @unchecked Sendable {
    let range: NSRange
    let color: NSColor
}

struct HighlightResult: @unchecked Sendable {
    var spans: [HighlightSpan] = []
    var background: NSColor?
    var status: String
    var milliseconds: Double = 0
}

// One actor owns the JSContext. It is never used concurrently or on the UI actor.
actor HighlightEngine {
    static let shared = HighlightEngine()
    static let explicitLimit = 100_000
    static let automaticLimit = 8_000
    private var highlighter: Highlighter?
    private var currentTheme: String?

    func render(_ text: String, language: String?, dark: Bool, enforceLimit: Bool = true) -> HighlightResult {
        guard !Task.isCancelled else { return HighlightResult(status: "已取消") }
        guard !text.isEmpty else { return HighlightResult(status: "等待输入") }
        let limit = language == nil ? Self.automaticLimit : Self.explicitLimit
        guard !enforceLimit || text.utf16.count <= limit else {
            return HighlightResult(status: language == nil ? "文本较长，请指定语言以启用高亮" : "大文本使用纯文本显示")
        }
        let start = Date()
        if highlighter == nil { highlighter = Highlighter() }
        guard let highlighter else { return HighlightResult(status: "高亮资源不可用，已使用纯文本") }
        let theme = dark ? "github-dark" : "github"
        if currentTheme != theme {
            guard highlighter.setTheme(theme, withFont: "Menlo", ofSize: 14) else {
                return HighlightResult(status: "主题不可用，已使用纯文本")
            }
            currentTheme = theme
        }
        highlighter.ignoreIllegals = true
        if let language, !highlighter.supportedLanguages().contains(language) {
            return HighlightResult(status: "不支持此语言，已使用纯文本")
        }
        guard let attributed = highlighter.highlight(text, as: language),
              Array(attributed.string.utf16) == Array(text.utf16) else {
            return HighlightResult(status: "高亮结果不兼容，已保留纯文本")
        }
        var spans: [HighlightSpan] = []
        attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let color = (value as? NSColor)?.usingColorSpace(.sRGB) {
                spans.append(HighlightSpan(range: range, color: color))
            }
        }
        return HighlightResult(spans: spans, background: highlighter.theme.themeBackgroundColour?.usingColorSpace(.sRGB), status: language?.uppercased() ?? "自动高亮", milliseconds: Date().timeIntervalSince(start) * 1000)
    }
}

@MainActor
final class HighlightTextView: NSTextView {
    var language: HighlightLanguage = .automatic { didSet { scheduleHighlight() } }
    var automaticHint: String? { didSet { scheduleHighlight() } }
    var onHighlight: ((String) -> Void)?
    private var generation = 0
    private var highlightTask: Task<Void, Never>?
    private(set) var lastAppliedGeneration = 0

    override func didChangeText() {
        super.didChangeText()
        scheduleHighlight()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        scheduleHighlight()
    }
    override func unmarkText() {
        super.unmarkText()
        scheduleHighlight()
    }

    func scheduleHighlight() {
        generation += 1
        let version = generation
        highlightTask?.cancel()
        guard language != .plaintext else { clearHighlight(); onHighlight?("纯文本"); return }
        guard !hasMarkedText() else { return }
        let source = string
        let selectedLanguage = language == .automatic ? automaticHint : language.rawValue
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let result = await HighlightEngine.shared.render(source, language: selectedLanguage, dark: dark)
            guard !Task.isCancelled, let self, self.generation == version,
                  !self.hasMarkedText(), self.string == source else { return }
            self.apply(result)
            self.lastAppliedGeneration = version
        }
    }

    private func clearHighlight() {
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: (string as NSString).length))
        backgroundColor = .textBackgroundColor
        enclosingScrollView?.backgroundColor = .textBackgroundColor
    }

    // Temporary layout attributes leave the document, typing attributes and undo untouched.
    private func apply(_ result: HighlightResult) {
        clearHighlight()
        for span in result.spans {
            layoutManager?.addTemporaryAttribute(.foregroundColor, value: span.color, forCharacterRange: span.range)
        }
        if let color = result.background {
            backgroundColor = color
            enclosingScrollView?.backgroundColor = color
        }
        onHighlight?(result.status)
    }
}
