// Created by lidawen.
import Foundation

struct ToolAction: Identifiable, Hashable {
    enum Effect: Hashable { case replace, preview(String), information }
    let id: String
    let title: String
    var localizedTitle: String { L10n.text(title) }
    let home: String
    var group = "其他操作"
    var effect: Effect = .replace
    var wholeDocument = false

    var outputFormat: String? {
        if case let .preview(format) = effect { return format }
        return nil
    }
}

struct ContentFormat: Identifiable, Hashable {
    let id: String
    let title: String
    var localizedTitle: String { L10n.text(title) }
    let symbol: String
    let primaryIDs: [String]
    var isOther = false
    var language: HighlightLanguage = .plaintext

    var actions: [ToolAction] {
        let own = FormatCatalog.actions.filter { $0.home == id }
        let common = FormatCatalog.commonFormatIDs.contains(id)
            ? FormatCatalog.actions.filter { FormatCatalog.commonActionIDs.contains($0.id) && $0.home != id } : []
        return own + common
    }
    var primaryActions: [ToolAction] { primaryIDs.compactMap { id in actions.first { $0.id == id } } }
}

struct ActionSearchResult: Identifiable {
    let format: ContentFormat
    let action: ToolAction?
    var id: String { format.id + "/" + (action?.id ?? "") }
    var title: String { action.map { format.localizedTitle + " › " + $0.localizedTitle } ?? format.localizedTitle }
}

enum FormatCatalog {
    static let formats: [ContentFormat] = [
        .init(id: "json", title: "JSON", symbol: "curlybraces", primaryIDs: ["FormatJSON", "MinifyJSON", "RemoveSlashes"], language: .json),
        .init(id: "yaml", title: "YAML", symbol: "list.bullet.indent", primaryIDs: ["YAMLtoJSON"], language: .yaml),
        .init(id: "csv", title: "CSV", symbol: "tablecells", primaryIDs: ["CSVtoJSON"]),
        .init(id: "xml", title: "XML / HTML", symbol: "chevron.left.forwardslash.chevron.right", primaryIDs: ["FormatXML", "MinifyXML"]),
        .init(id: "css", title: "CSS", symbol: "number", primaryIDs: ["FormatCSS", "MinifyCSS"]),
        .init(id: "sql", title: "SQL", symbol: "cylinder", primaryIDs: ["FormatSQL", "MinifySQL"]),
        .init(id: "javascript", title: "JavaScript", symbol: "chevron.left.forwardslash.chevron.right", primaryIDs: ["EvalJavascript"], language: .javascript),
        .init(id: "markdown", title: "Markdown", symbol: "text.badge.checkmark", primaryIDs: ["MarkdownQuote"]),
        .init(id: "text", title: "文本", symbol: "text.alignleft", primaryIDs: ["RemoveSlashes", "Trim", "RemoveDuplicates"]),
        .init(id: "url", title: "URL / 查询串", symbol: "link", primaryIDs: ["URLEncode", "URLDecode", "QueryToJson"], isOther: true),
        .init(id: "base64", title: "Base64", symbol: "arrow.left.arrow.right", primaryIDs: ["Base64Encode", "Base64Decode"], isOther: true),
        .init(id: "jwt", title: "JWT", symbol: "key", primaryIDs: ["JWTDecode"], isOther: true),
        .init(id: "hash", title: "哈希", symbol: "number.square", primaryIDs: ["SHA256", "MD5"], isOther: true),
        .init(id: "number", title: "数字与颜色", symbol: "number.circle", primaryIDs: ["DecimalToHex", "hex2rgb", "SumAll"], isOther: true),
        .init(id: "date", title: "日期与时间", symbol: "clock", primaryIDs: ["DateToTimestamp", "DateToUTC"], isOther: true),
        .init(id: "localization", title: "本地化", symbol: "globe", primaryIDs: ["AndroidIOSStrings", "IOSAndroidStrings"], isOther: true),
        .init(id: "php", title: "PHP 序列化", symbol: "shippingbox", primaryIDs: ["PhpUnserialize"], isOther: true),
        .init(id: "shell", title: "Shell", symbol: "terminal", primaryIDs: ["FishHexPathConverter"], isOther: true),
        .init(id: "developer", title: "开发工具", symbol: "hammer", primaryIDs: ["Test"], isOther: true)
    ]
    static let commonFormatIDs: Set<String> = ["json", "yaml", "csv", "xml", "css", "sql", "javascript", "markdown"]
    static let commonActionIDs: Set<String> = ["RemoveSlashes", "AddSlashes", "Trim", "RemoveDuplicates", "CountCharacters", "CountLines", "CountWords"]
    static func format(_ id: String) -> ContentFormat? { formats.first { $0.id == id } }
    static func action(_ id: String) -> ToolAction? { actions.first { $0.id == id } }
    static func home(for id: String) -> String { format(id)?.id ?? action(id)?.home ?? "text" }
    static func title(_ id: String) -> String { format(id)?.localizedTitle ?? id }
    static func search(_ query: String, tools: [Tool]) -> [ActionSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let metadata = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
        return formats.flatMap { format in
            var matches: [ActionSearchResult] = []
            if "\(format.title) \(format.localizedTitle) \(format.id)".localizedCaseInsensitiveContains(query) { matches.append(.init(format: format, action: nil)) }
            matches += format.actions.filter { action in
                let tool = metadata[action.id]
                return "\(action.title) \(action.localizedTitle) \(action.id) \(tool?.name ?? "") \(tool?.tags ?? "") \(tool?.description ?? "")".localizedCaseInsensitiveContains(query)
            }.map { .init(format: format, action: $0) }
            return matches
        }
    }

    // Explicit routing is also the migration map; never infer ownership from substrings.
    static let actions: [ToolAction] = [
        .init(id: "FormatJSON", title: "格式化", home: "json"),
        .init(id: "MinifyJSON", title: "压缩", home: "json"),
        .init(id: "SortJSON", title: "排序（含数组）", home: "json"),
        .init(id: "JSONtoYAML", title: "转为 YAML", home: "json", group: "转换", effect: .preview("yaml")),
        .init(id: "JSONtoCSV", title: "转为 CSV", home: "json", group: "转换", effect: .preview("csv")),
        .init(id: "JsonToQuery", title: "转为 URL 查询串", home: "json", group: "转换", effect: .preview("url")),
        .init(id: "YAMLtoJSON", title: "转为 JSON", home: "yaml", group: "转换", effect: .preview("json")),
        .init(id: "CSVtoJSON", title: "转为 JSON", home: "csv", group: "转换", effect: .preview("json")),
        .init(id: "FormatXML", title: "格式化", home: "xml"), .init(id: "MinifyXML", title: "压缩", home: "xml"),
        .init(id: "HTMLDecode", title: "解码 HTML 实体", home: "xml", group: "编码"),
        .init(id: "HTMLEncode", title: "编码 HTML 实体", home: "xml", group: "编码"),
        .init(id: "HTMLEncodeAll", title: "编码全部字符", home: "xml", group: "编码"),
        .init(id: "FormatCSS", title: "格式化", home: "css"), .init(id: "MinifyCSS", title: "压缩", home: "css"),
        .init(id: "FormatSQL", title: "格式化", home: "sql"), .init(id: "MinifySQL", title: "压缩", home: "sql"),
        .init(id: "EvalJavascript", title: "运行", home: "javascript"),
        .init(id: "MarkdownQuote", title: "引用", home: "markdown"),
        .init(id: "RemoveSlashes", title: "去反斜杠", home: "text", group: "转义"),
        .init(id: "AddSlashes", title: "添加反斜杠", home: "text", group: "转义"),
        .init(id: "Trim", title: "修剪首尾空白", home: "text", group: "清理"),
        .init(id: "RemoveDuplicates", title: "去除重复行", home: "text", group: "行操作"),
        .init(id: "CountCharacters", title: "字符统计", home: "text", group: "统计", effect: .information),
        .init(id: "CountLines", title: "行数统计", home: "text", group: "统计", effect: .information),
        .init(id: "CountWords", title: "词数统计", home: "text", group: "统计", effect: .information),
        .init(id: "CamelCase", title: "camelCase", home: "text", group: "大小写与命名"),
        .init(id: "KebabCase", title: "kebab-case", home: "text", group: "大小写与命名"),
        .init(id: "SnakeCase", title: "snake_case", home: "text", group: "大小写与命名"),
        .init(id: "StartCase", title: "单词首字母大写", home: "text", group: "大小写与命名"),
        .init(id: "SpongeCase", title: "交替大小写", home: "text", group: "大小写与命名"),
        .init(id: "Upcase", title: "大写", home: "text", group: "大小写与命名"),
        .init(id: "Downcase", title: "小写", home: "text", group: "大小写与命名"),
        .init(id: "Deburr", title: "移除重音符号", home: "text", group: "清理"),
        .init(id: "ReplaceSmartQuotes", title: "替换弯引号", home: "text", group: "清理"),
        .init(id: "Collapse", title: "合并为一行", home: "text", group: "行操作", wholeDocument: true),
        .init(id: "Sort", title: "按字母排序行", home: "text", group: "行操作"),
        .init(id: "NatSort", title: "自然排序行", home: "text", group: "行操作"),
        .init(id: "ReverseLines", title: "倒序行", home: "text", group: "行操作"),
        .init(id: "ShuffleLines", title: "打乱行", home: "text", group: "行操作"),
        .init(id: "ReverseString", title: "反转文本", home: "text"),
        .init(id: "LoremIpsum", title: "生成占位文本", home: "text"),
        .init(id: "Rot13", title: "ROT13", home: "text", group: "编码"),
        .init(id: "URLEncode", title: "URL 编码", home: "url", group: "编码"),
        .init(id: "URLDecode", title: "URL 解码", home: "url", group: "编码"),
        .init(id: "URLEntitiesEncode", title: "编码全部 URL 字符", home: "url", group: "编码"),
        .init(id: "URLEntitiesDecode", title: "解码全部 URL 字符", home: "url", group: "编码"),
        .init(id: "URLDefang", title: "Defang", home: "url"), .init(id: "URLRefang", title: "Refang", home: "url"),
        .init(id: "QueryToJson", title: "查询串转 JSON", home: "url", group: "转换", effect: .preview("json")),
        .init(id: "Base64Encode", title: "编码", home: "base64", effect: .preview("base64")),
        .init(id: "Base64Decode", title: "解码", home: "base64", effect: .preview("text")),
        .init(id: "JWTDecode", title: "解码为 JSON", home: "jwt", effect: .preview("json")),
        .init(id: "MD5", title: "MD5", home: "hash", effect: .preview("text")),
        .init(id: "SHA1", title: "SHA-1", home: "hash", effect: .preview("text")),
        .init(id: "SHA256", title: "SHA-256", home: "hash", effect: .preview("text")),
        .init(id: "SHA512", title: "SHA-512", home: "hash", effect: .preview("text")),
        .init(id: "DecimalToBinary", title: "十进制 → 二进制", home: "number", effect: .preview("text")),
        .init(id: "BinaryToDecimal", title: "二进制 → 十进制", home: "number", effect: .preview("text")),
        .init(id: "DecimalToHex", title: "十进制 → 十六进制", home: "number", effect: .preview("text")),
        .init(id: "HexToDecimal", title: "十六进制 → 十进制", home: "number", effect: .preview("text")),
        .init(id: "ASCIIToHex", title: "ASCII → Hex", home: "number", effect: .preview("text"), wholeDocument: true),
        .init(id: "HexToASCII", title: "Hex → ASCII", home: "number", effect: .preview("text"), wholeDocument: true),
        .init(id: "hex2rgb", title: "Hex → RGB", home: "number", effect: .preview("text")),
        .init(id: "SumAll", title: "求和", home: "number"),
        .init(id: "DateToTimestamp", title: "转为时间戳", home: "date", effect: .preview("text")),
        .init(id: "DateToUTC", title: "转为 UTC", home: "date", effect: .preview("text")),
        .init(id: "AndroidIOSStrings", title: "Android → iOS", home: "localization", effect: .preview("text"), wholeDocument: true),
        .init(id: "IOSAndroidStrings", title: "iOS → Android", home: "localization", effect: .preview("xml"), wholeDocument: true),
        .init(id: "PhpUnserialize", title: "转为 JSON", home: "php", effect: .preview("json")),
        .init(id: "FishHexPathConverter", title: "PATH 转义", home: "shell"),
        .init(id: "Test", title: "测试脚本", home: "developer", wholeDocument: true)
    ]
}
