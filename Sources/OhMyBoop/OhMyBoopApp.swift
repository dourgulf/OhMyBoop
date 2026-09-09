// Created by lidawen.
import SwiftUI

@main
enum EntryPoint {
    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == "--validate-highlighter" {
            let samples = ["json": "{\"message\":\"你好 🌍\",\"value\":42}", "yaml": "message: 你好 🌍\nvalue: 42", "javascript": "const value = 42; // 你好 🌍"]
            var report: [String: [String: Any]] = [:]
            var valid = true
            for (language, sample) in samples {
                for dark in [false, true] {
                    let result = await HighlightEngine.shared.render(sample, language: language, dark: dark)
                    report["\(language)-\(dark ? "dark" : "light")"] = ["ranges": result.spans.count, "status": result.status]
                    valid = valid && result.spans.count > 1
                }
            }
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: arguments[2]))
                exit(valid ? 0 : 1)
            } catch { exit(1) }
        }
        if arguments.count == 4, arguments[1] == "--script-worker" {
            do {
                let request = try JSONDecoder().decode(ScriptRequest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
                let result: ScriptResult
                do { result = try ScriptEngine.execute(request) }
                catch {
                    result = ScriptResult(text: request.text, selectionLocation: request.selectionLocation, selectionLength: request.selectionLength, error: error.localizedDescription)
                }
                try JSONEncoder().encode(result).write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
            } catch { exit(1) }
            return
        }
        OhMyBoopApp.main()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var workspace: Workspace?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.save()
        return .terminateNow
    }
}

struct OhMyBoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var workspace = Workspace()

    var body: some Scene {
        Window("OhMyBoop", id: "main") {
            ContentView(workspace: workspace)
                .onAppear { delegate.workspace = workspace }
                .onDisappear { workspace.save() }
                .tint(Color(red: 0.12, green: 0.55, blue: 0.45))
        }
        .defaultSize(width: 1120, height: 740)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("处理") {
                if let id = workspace.selectedID {
                    let session = workspace.session(for: id)
                    if let action = session.lastAction {
                        Button(action.title) { session.run(action) }
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(session.isRunning)
                    }
                }
            }
        }
        Settings {
            EditorSettingsView(preferences: .shared)
        }
    }
}
