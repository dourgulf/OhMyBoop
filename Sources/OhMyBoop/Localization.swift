// Created by lidawen.
import Foundation

enum L10n {
    static let preferenceKey = "app.language"
    // A process-only override lets CI exercise both languages without touching user preferences.
    static let language = resolveLanguage(ProcessInfo.processInfo.environment["OHMYBOOP_LANGUAGE"] ?? UserDefaults.standard.string(forKey: preferenceKey), preferred: Locale.preferredLanguages)
    static let locale = Locale(identifier: language)

    static func resolveLanguage(_ selection: String?, preferred: [String]) -> String {
        if selection == "en" || selection == "zh-Hans" { return selection! }
        for item in preferred {
            if item.hasPrefix("zh") { return "zh-Hans" }
            if item.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
    static func bundle(for language: String) -> Bundle {
        // SwiftPM lowercases lproj folder names; Xcode preserves their spelling.
        for name in [language, language.lowercased()] {
            if let url = resourceBundle.resourceURL?.appendingPathComponent(name + ".lproj"),
               let bundle = Bundle(url: url) { return bundle }
        }
        return resourceBundle
    }
    static func text(_ key: String, _ arguments: String..., language: String = L10n.language) -> String {
        format(key, arguments: arguments, language: language)
    }
    static func format(_ key: String, arguments: [String], language: String = L10n.language) -> String {
        let template = bundle(for: language).localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: Locale(identifier: language), arguments: arguments.map { $0 as CVarArg })
    }

    // Keep arbitrary third-party exception text verbatim. Only translate known messages.
    static func scriptMessage(_ message: String, arguments: [String] = [], language: String = L10n.language) -> String {
        let patterns = [(" characters", "字符数：%@"), (" lines", "行数：%@"), (" words", "词数：%@"), (" lines collapsed", "已合并 %@ 行"), (" lines removed", "已移除 %@ 行")]
        for (suffix, key) in patterns where message.hasSuffix(suffix) {
            let number = String(message.dropLast(suffix.count))
            if !number.isEmpty && number.allSatisfy(\.isNumber) { return format(key, arguments: [number], language: language) }
        }
        return format(message, arguments: arguments, language: language)
    }

    static func saveLanguage(_ selection: String, defaults: UserDefaults = .standard) {
        let valid = ["system", "en", "zh-Hans"].contains(selection) ? selection : "system"
        defaults.set(valid, forKey: preferenceKey)
        // AppKit's standard menus read this at launch; keep them aligned with custom UI.
        if valid == "system" { defaults.removeObject(forKey: "AppleLanguages") }
        else { defaults.set([valid], forKey: "AppleLanguages") }
    }
}
