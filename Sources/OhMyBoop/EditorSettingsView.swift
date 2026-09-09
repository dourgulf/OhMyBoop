// Created by lidawen.
import SwiftUI

struct EditorSettingsView: View {
    @Bindable var preferences: EditorPreferences

    var body: some View {
        Form {
            Section("编辑器") {
                Picker("字体", selection: $preferences.fontName) {
                    Text("系统等宽字体").tag(EditorPreferences.systemFontID)
                    ForEach(EditorPreferences.fontNames, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                }
                Stepper(value: $preferences.fontSize, in: 10...32, step: 1) {
                    LabeledContent("字号") {
                        Text("\(Int(preferences.fontSize)) pt").monospacedDigit()
                    }
                }
                Text("应用于所有编辑器和结果预览，自动保存。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("预览") {
                Text(verbatim: "{\n  \"text\": \"你好\",\n  \"count\": 42\n}")
                    .font(Font(preferences.font))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            }
            Button("恢复默认字体和字号") { preferences.reset() }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
    }
}
