// Created by lidawen.
import Foundation
import JavaScriptCore

enum EngineError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct ScriptRequest: Codable, Sendable {
    let toolID: String
    let text: String
    let selectionLocation: Int
    let selectionLength: Int
    var language: String? = nil
}

struct ScriptResult: Codable, Sendable {
    var text: String
    var selectionLocation: Int
    var selectionLength: Int
    var info: String?
    var error: String?
    var errorOffset: Int? = nil
}

enum ScriptEngine {
    // Each invocation owns a fresh VM. Only bundled modules are exposed; no native I/O bridge.
    static func execute(_ request: ScriptRequest) throws -> ScriptResult {
        let language = L10n.resolveLanguage(request.language, preferred: [L10n.language])
        guard try Catalog.load().contains(where: { $0.id == request.toolID }), let context = JSContext() else {
            throw EngineError.message(L10n.text("找不到功能：%@", request.toolID))
        }
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() ?? "JavaScript error" }
        let libraries = try FileManager.default.contentsOfDirectory(at: Catalog.root.appendingPathComponent("lib"), includingPropertiesForKeys: nil)
        var sources: [String: String] = [:]
        for url in libraries where url.pathExtension == "js" {
            sources[url.deletingPathExtension().lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
        }
        context.setObject(sources, forKeyedSubscript: "__sources" as NSString)
        context.evaluateScript("""
        var global = this; var globalThis = this;
        var __cache = {};
        function require(name) {
            var key = name.replace(/^@boop\\//, '').replace(/\\.js$/, '');
            if (!Object.prototype.hasOwnProperty.call(__sources, key)) throw new Error('Unknown module: ' + name);
            if (__cache[key]) return __cache[key].exports;
            var module = {exports: {}}; __cache[key] = module;
            new Function('module', 'exports', 'require', __sources[key])(module, module.exports, require);
            return module.exports;
        }
        """)
        context.setObject(request.text, forKeyedSubscript: "__input" as NSString)
        let count = (request.text as NSString).length
        let location = min(max(0, request.selectionLocation), count)
        let length = min(max(0, request.selectionLength), count - location)
        context.setObject(location, forKeyedSubscript: "__location" as NSString)
        context.setObject(length, forKeyedSubscript: "__length" as NSString)
        context.evaluateScript("""
        var __state = {
            fullText: __input, info: null, error: null,
            postInfo: function(message) { this.info = String(message); },
            postError: function(message, offset, arguments) {
                this.error = String(message);
                this.errorArguments = arguments || [];
                this.errorOffset = typeof offset === 'number' ? (__length ? __location : 0) + offset : null;
            }
        };
        Object.defineProperty(__state, 'text', {
            get: function() { return __length ? this.fullText.substr(__location, __length) : this.fullText; },
            set: function(value) {
                value = String(value == null ? '' : value);
                if (__length) {
                    this.fullText = this.fullText.slice(0, __location) + value + this.fullText.slice(__location + __length);
                    __length = value.length;
                } else { this.fullText = value; }
            }
        });
        """)
        let source = try String(contentsOf: Catalog.root.appendingPathComponent(request.toolID + ".js"), encoding: .utf8)
        context.evaluateScript(source + "\nmain(__state);", withSourceURL: URL(fileURLWithPath: request.toolID + ".js"))
        guard exception == nil else { throw EngineError.message(exception!) }
        let state = context.objectForKeyedSubscript("__state")!
        let error = state.forProperty("error")!
        let info = state.forProperty("info")!
        let errorText = error.isNull || error.isUndefined ? nil : error.toString()
        let errorArguments = state.forProperty("errorArguments")?.toArray() as? [String] ?? []
        let offset = state.forProperty("errorOffset")!
        let errorOffset = offset.isNumber ? Int(exactly: offset.toDouble()) : nil
        return ScriptResult(
            text: errorText == nil ? state.forProperty("fullText").toString() : request.text,
            selectionLocation: location,
            selectionLength: Int(context.objectForKeyedSubscript("__length").toInt32()),
            info: info.isNull || info.isUndefined ? nil : L10n.scriptMessage(info.toString(), language: language),
            error: errorText.map { L10n.scriptMessage($0, arguments: errorArguments, language: language) },
            errorOffset: errorOffset
        )
    }

    // A subprocess keeps large transformations and Eval Javascript off the UI thread,
    // and allows an infinite script to be stopped without destroying the editor.
    static func run(_ request: ScriptRequest, timeout: TimeInterval = 8, executableURL: URL? = Bundle.main.executableURL) async throws -> ScriptResult {
        var localizedRequest = request
        localizedRequest.language = request.language ?? L10n.language
        let request = localizedRequest
        return try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let input = folder.appendingPathComponent("input.json")
            let output = folder.appendingPathComponent("output.json")
            try JSONEncoder().encode(request).write(to: input, options: .atomic)
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--script-worker", input.path, output.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                throw EngineError.message(L10n.text("执行超过 %@ 秒，已停止。原文已保留。", String(Int(timeout))))
            }
            // isRunning is already false. A second synchronous wait can block a
            // Swift concurrency worker despite the child having exited.
            guard process.terminationStatus == 0 else { throw EngineError.message(L10n.text("执行进程异常退出，原文已保留。")) }
            return try JSONDecoder().decode(ScriptResult.self, from: Data(contentsOf: output))
        }.value
    }
}
