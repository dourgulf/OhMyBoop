// Created by lidawen.
import AppKit
import Observation

@MainActor @Observable
final class EditorPreferences {
    static let shared = EditorPreferences()
    static let changed = Notification.Name("OhMyBoop.editorFontChanged")
    static let systemFontID = "system-monospace"
    static let fontNames = NSFontManager.shared.availableFonts.filter {
        !$0.hasPrefix(".") && NSFont(name: $0, size: 14)?.isFixedPitch == true
    }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    @ObservationIgnored private let defaults: UserDefaults
    private var storedFontName: String
    private var storedFontSize: Double
    var fontName: String {
        get { storedFontName }
        set {
            let value = Self.fontNames.contains(newValue) ? newValue : Self.systemFontID
            guard storedFontName != value else { return }
            storedFontName = value
            save()
        }
    }
    var fontSize: Double {
        get { storedFontSize }
        set {
            let value = Self.validSize(newValue)
            guard storedFontSize != value else { return }
            storedFontSize = value
            save()
        }
    }
    var font: NSFont {
        if fontName != Self.systemFontID, let font = NSFont(name: fontName, size: fontSize) { return font }
        return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "editor.fontName") ?? Self.systemFontID
        storedFontName = Self.fontNames.contains(saved) ? saved : Self.systemFontID
        storedFontSize = Self.validSize(defaults.object(forKey: "editor.fontSize") as? Double ?? 14)
    }

    private static func validSize(_ size: Double) -> Double { size.isFinite ? min(32, max(10, size)) : 14 }
    private func save() {
        defaults.set(fontName, forKey: "editor.fontName")
        defaults.set(fontSize, forKey: "editor.fontSize")
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    func reset() { fontName = Self.systemFontID; fontSize = 14 }
}
