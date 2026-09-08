// Created by lidawen.
import AppKit
import SwiftTreeSitter
import TreeSitterJSON
import TreeSitterYAML
import TreeSitterJavaScript

enum HighlightLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic, plaintext, json, yaml, javascript
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
    var parseMilliseconds: Double = 0
    var incremental: Bool = false
    var paintedRange: NSRange?
}

// Each editor owns its parser and previous tree. Parsing and queries run off the UI actor.
actor HighlightEngine {
    static let shared = HighlightEngine()
    static let explicitLimit = 100_000
    static let automaticLimit = 8_000
    private var parser: Parser?
    private var query: Query?
    private var tree: MutableTree?
    private var previous: [UInt16] = []
    private var currentLanguage: String?

    func render(_ text: String, language: String?, dark: Bool, enforceLimit: Bool = true, visibleRange: NSRange? = nil) -> HighlightResult {
        let start = Date()
        guard !Task.isCancelled else { return HighlightResult(status: "已取消") }
        guard !text.isEmpty else { tree = nil; previous = []; return HighlightResult(status: "等待输入") }
        let limit = language == nil ? Self.automaticLimit : Self.explicitLimit
        guard !enforceLimit || text.utf16.count <= limit else {
            tree = nil; previous = []
            return HighlightResult(status: language == nil ? "文本较长，请指定语言以启用高亮" : "大文本使用纯文本显示")
        }
        let units = Array(text.utf16)
        // Conservative application heuristic; Tree-sitter itself does not detect languages.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = language ?? ((trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) ? "json" : "")
        guard ["json", "yaml", "javascript"].contains(selected) else {
            tree = nil; previous = []
            return HighlightResult(status: language == nil ? "请选择语言，当前使用纯文本" : "不支持此语言，已使用纯文本")
        }
        do {
            if currentLanguage != selected || parser == nil {
                let pointer = selected == "json" ? tree_sitter_json() : selected == "yaml" ? tree_sitter_yaml() : tree_sitter_javascript()
                let grammar = Language(pointer!)
                let newParser = Parser()
                try newParser.setLanguage(grammar)
                newParser.timeout = 1
                let url = Catalog.root.deletingLastPathComponent().appendingPathComponent("queries/\(selected).scm")
                let newQuery = try Query(language: grammar, url: url)
                parser = newParser; query = newQuery; tree = nil; previous = []; currentLanguage = selected
            }
            guard let parser, let query else { return HighlightResult(status: "解析器不可用，已使用纯文本") }
            let incremental = tree != nil && previous != units
            if incremental {
                var prefix = 0
                while prefix < min(previous.count, units.count) && previous[prefix] == units[prefix] { prefix += 1 }
                // Keep edits on Unicode scalar boundaries, including emoji sharing a high surrogate.
                if prefix > 0 && prefix < units.count && (0xDC00...0xDFFF).contains(units[prefix]) { prefix -= 1 }
                var suffix = 0
                while suffix < min(previous.count, units.count) - prefix && previous[previous.count - 1 - suffix] == units[units.count - 1 - suffix] { suffix += 1 }
                if suffix > 0 && (0xDC00...0xDFFF).contains(units[units.count - suffix]) { suffix -= 1 }
                let oldEnd = previous.count - suffix, newEnd = units.count - suffix
                tree?.edit(InputEdit(startByte: prefix * 2, oldEndByte: oldEnd * 2, newEndByte: newEnd * 2,
                                     startPoint: Self.point(previous, prefix), oldEndPoint: Self.point(previous, oldEnd), newEndPoint: Self.point(units, newEnd)))
            }
            let parseStart = Date()
            if tree == nil || previous != units {
                let data = text.data(using: .utf16LittleEndian)!
                tree = parser.parse(tree: tree, readBlock: { byte, _ in
                    let offset = Int(byte)
                    guard offset < data.count else { return nil }
                    return data.subdata(in: offset..<min(offset + 8192, data.count))
                })
            }
            let parseMS = Date().timeIntervalSince(parseStart) * 1000
            guard let tree else { parser.reset(); previous = []; return HighlightResult(status: "解析超时，已使用纯文本") }
            previous = units
            guard !Task.isCancelled else { return HighlightResult(status: "已取消") }
            let fullRange = NSRange(location: 0, length: units.count)
            let paintRange = visibleRange.map { NSIntersectionRange($0, fullRange) } ?? fullRange
            let cursor = query.execute(in: tree)
            // Query the whole tree within a viewport range, preserving enclosing syntax context.
            // A capture may extend beyond the viewport (multiline strings/comments).
            cursor.setRange(paintRange)
            let captures = paintRange.length == 0 ? [] : cursor.resolve(with: .init(string: text)).highlights()
            var spans = [HighlightSpan(range: paintRange, color: Self.color("text", dark: dark))]
            for capture in captures {
                guard NSMaxRange(capture.range) <= units.count else { continue }
                let clipped = NSIntersectionRange(capture.range, paintRange)
                guard clipped.length > 0 else { continue }
                spans.append(HighlightSpan(range: clipped, color: Self.color(capture.name, dark: dark)))
            }
            return HighlightResult(spans: spans, background: Self.rgb(dark ? 0x0d1117 : 0xffffff), status: "\(selected.uppercased()) · 语法高亮", milliseconds: Date().timeIntervalSince(start) * 1000, parseMilliseconds: parseMS, incremental: incremental, paintedRange: paintRange)
        } catch {
            tree = nil; previous = []; parser = nil
            return HighlightResult(status: "语法资源不可用，已使用纯文本")
        }
    }

    private static func point(_ units: [UInt16], _ end: Int) -> Point {
        var row = 0, column = 0
        for unit in units.prefix(end) {
            if unit == 10 { row += 1; column = 0 } else { column += 2 }
        }
        return Point(row: row, column: column)
    }
    private static func rgb(_ value: Int) -> NSColor {
        NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
    }
    private static func color(_ name: String, dark: Bool) -> NSColor {
        let value: Int
        if name.contains("comment") { value = dark ? 0x8b949e : 0x6a737d }
        else if name.contains("key") || name.contains("property") || name.contains("number") || name.contains("constant") || name.contains("boolean") { value = dark ? 0x79c0ff : 0x005cc5 }
        else if name.hasPrefix("string") { value = dark ? 0xa5d6ff : 0x032f62 }
        else if name.hasPrefix("keyword") || name.hasPrefix("operator") { value = dark ? 0xff7b72 : 0xd73a49 }
        else if name.hasPrefix("function") { value = dark ? 0xd2a8ff : 0x6f42c1 }
        else { value = dark ? 0xc9d1d9 : 0x24292e }
        return rgb(value)
    }
}

@MainActor
final class HighlightTextView: NSTextView {
    var language: HighlightLanguage = .automatic { didSet { scheduleHighlight() } }
    var automaticHint: String? { didSet { scheduleHighlight() } }
    var onHighlight: ((String) -> Void)?
    private let engine = HighlightEngine()
    private var generation = 0
    private var highlightTask: Task<Void, Never>?
    private(set) var lastAppliedGeneration = 0
    private(set) var lastAppliedRange: NSRange?
    private(set) var lastApplicationMilliseconds: Double = 0
    private var requestedRange: NSRange?

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

    // Scroll/resize requests reuse the parser tree; they do not wait for the typing debounce.
    func scheduleViewportHighlight() {
        guard requestedRange != viewportRange() else { return }
        scheduleHighlight(delay: 30)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleViewportHighlight()
    }

    private func viewportRange() -> NSRange {
        let full = NSRange(location: 0, length: (string as NSString).length)
        guard let scroll = enclosingScrollView, let layoutManager, let textContainer,
              scroll.contentSize.height > 0 else { return full }
        var rect = visibleRect
        rect = rect.insetBy(dx: 0, dy: -rect.height)
        rect.origin.x -= textContainerOrigin.x
        rect.origin.y -= textContainerOrigin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        return NSIntersectionRange(layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil), full)
    }

    func scheduleHighlight(delay: Int = 180) {
        generation += 1
        let version = generation
        highlightTask?.cancel()
        guard language != .plaintext else { clearHighlight(); onHighlight?("纯文本"); return }
        guard !hasMarkedText() else { return }
        let engine = self.engine
        let source = string
        let range = viewportRange()
        requestedRange = range
        let selectedLanguage = language == .automatic ? automaticHint : language.rawValue
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            let result = await engine.render(source, language: selectedLanguage, dark: dark, visibleRange: range)
            guard !Task.isCancelled, let self, self.generation == version,
                  !self.hasMarkedText(), self.string == source else { return }
            self.apply(result)
            self.lastAppliedGeneration = version
        }
    }

    private func clearHighlight() {
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: (string as NSString).length))
        lastAppliedRange = nil
        backgroundColor = .textBackgroundColor
        enclosingScrollView?.backgroundColor = .textBackgroundColor
    }

    // Temporary layout attributes leave the document, typing attributes and undo untouched.
    private func apply(_ result: HighlightResult) {
        let start = Date()
        clearHighlight()
        for span in result.spans {
            layoutManager?.addTemporaryAttribute(.foregroundColor, value: span.color, forCharacterRange: span.range)
        }
        if let color = result.background {
            backgroundColor = color
            enclosingScrollView?.backgroundColor = color
        }
        lastAppliedRange = result.paintedRange
        lastApplicationMilliseconds = Date().timeIntervalSince(start) * 1000
        onHighlight?(result.status)
    }
}
