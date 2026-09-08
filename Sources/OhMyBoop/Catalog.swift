// Created by lidawen.
import Foundation

struct Tool: Identifiable, Decodable, Hashable {
    var id: String = ""
    let name: String
    let description: String
    let author: String
    let tags: String

    enum CodingKeys: String, CodingKey { case name, description, author, tags }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try values.decodeIfPresent(String.self, forKey: .author) ?? "Boop contributors"
        tags = try values.decodeIfPresent(String.self, forKey: .tags) ?? ""
    }

    var category: String {
        let key = id.lowercased()
        if key.contains("format") || key.contains("minify") { return "格式化与压缩" }
        if key.contains("json") || key.contains("yaml") || key.contains("csv") || key.contains("strings") { return "数据转换" }
        if key.contains("sha") || key == "md5" || key == "rot13" { return "哈希与加密" }
        if key.contains("encode") || key.contains("decode") || key.contains("url") || key.contains("ascii") { return "编码与解码" }
        if key.contains("date") || key.contains("timestamp") || key.contains("utc") { return "日期与时间" }
        if key.contains("decimal") || key.contains("binary") || key.contains("hex") || key.contains("sum") { return "数字与颜色" }
        return "文本工具"
    }

    var symbol: String {
        switch category {
        case "格式化与压缩": "curlybraces"
        case "数据转换": "arrow.left.arrow.right"
        case "哈希与加密": "number"
        case "编码与解码": "link"
        case "日期与时间": "clock"
        case "数字与颜色": "number.square"
        default: "text.alignleft"
        }
    }
}

enum Catalog {
    static let root: URL = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("OhMyBoop_OhMyBoop.bundle"),
           let bundle = Bundle(url: url), let scripts = bundle.url(forResource: "scripts", withExtension: nil) {
            return scripts
        }
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "scripts", withExtension: nil)!
        #else
        return Bundle.main.url(forResource: "scripts", withExtension: nil)!
        #endif
    }()
    static let categories = ["格式化与压缩", "数据转换", "编码与解码", "哈希与加密", "文本工具", "数字与颜色", "日期与时间"]

    static func load() throws -> [Tool] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "js" }
            .map { url in
                let source = try String(contentsOf: url, encoding: .utf8)
                guard let start = source.range(of: "/**"), let end = source.range(of: "**/", range: start.upperBound..<source.endIndex) else {
                    throw EngineError.message("无法读取工具信息：\(url.lastPathComponent)")
                }
                let metadata = String(source[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                var tool = try JSONDecoder().decode(Tool.self, from: Data(metadata.utf8))
                tool.id = url.deletingPathExtension().lastPathComponent
                return tool
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
