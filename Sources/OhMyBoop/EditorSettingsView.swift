// Created by lidawen.
import SwiftUI

struct EditorSettingsView: View {
    @Bindable var preferences: EditorPreferences
    @AppStorage(L10n.preferenceKey) private var appLanguage = "system"

    var body: some View {
        Form {
            Section(L10n.text("语言")) {
                Picker(L10n.text("语言"), selection: $appLanguage) {
                    Text(L10n.text("跟随系统")).tag("system")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                    Text(verbatim: "English").tag("en")
                }
                .onChange(of: appLanguage) { _, value in L10n.saveLanguage(value) }
                Text(L10n.text("重启应用后生效。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("编辑器")) {
                Picker(L10n.text("字体"), selection: $preferences.fontName) {
                    Text(L10n.text("系统等宽字体")).tag(EditorPreferences.systemFontID)
                    ForEach(EditorPreferences.fontNames, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                }
                Stepper(value: $preferences.fontSize, in: 10...32, step: 1) {
                    LabeledContent(L10n.text("字号")) {
                        Text("\(Int(preferences.fontSize)) pt").monospacedDigit()
                    }
                }
                Text(L10n.text("应用于所有编辑器和结果预览，自动保存。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("预览")) {
                Text(verbatim: "{\n  \"text\": \"你好\",\n  \"count\": 42\n}")
                    .font(Font(preferences.font))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            }
            Button(L10n.text("恢复默认字体和字号")) { preferences.reset() }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 610)
    }
}
