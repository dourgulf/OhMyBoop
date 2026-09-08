// Created by lidawen.
import SwiftUI

@main
enum EntryPoint {
    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == "--validate-highlighter" {
            let sample = "{\"message\":\"你好 🌍\",\"value\":42,\"enabled\":true}"
            let light = await HighlightEngine.shared.render(sample, language: "json", dark: false)
            let dark = await HighlightEngine.shared.render(sample, language: "json", dark: true)
            do {
                let report: [String: Any] = ["lightRanges": light.spans.count, "darkRanges": dark.spans.count, "lightStatus": light.status, "darkStatus": dark.status]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: arguments[2]))
                exit(light.spans.isEmpty || dark.spans.isEmpty ? 1 : 0)
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
        }
    }
}
