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
