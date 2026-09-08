// Created by lidawen.
import SwiftUI

@main
enum EntryPoint {
    static func main() {
        let arguments = CommandLine.arguments
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
