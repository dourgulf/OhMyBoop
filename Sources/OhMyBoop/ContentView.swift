// Created by lidawen.
import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var search = ""
    @State private var otherExpanded = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill").font(.title2).foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OhMyBoop").font(.headline)
                        Text("你的开发工具箱").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索格式或动作…", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).help("清除搜索")
                    }
                }.padding(9).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8)).padding(.horizontal, 14)
                if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    List(selection: $workspace.selectedID) {
                        Section("格式与文本") {
                            ForEach(FormatCatalog.formats.filter { !$0.isOther }) { format in
                                Label(format.title, systemImage: format.symbol).padding(.vertical, 4).tag(format.id)
                            }
                        }
                        DisclosureGroup("其他数据类型", isExpanded: $otherExpanded) {
                            ForEach(FormatCatalog.formats.filter(\.isOther)) { format in
                                Label(format.title, systemImage: format.symbol).padding(.vertical, 4).tag(format.id)
                            }
                        }
                    }.listStyle(.sidebar)
                } else {
                    FormatSearchResults(query: search, workspace: workspace)
                }
                Divider()
                Text("\(workspace.tools.count) 个动作 · 本地处理")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }.frame(minWidth: 210, idealWidth: 240, maxWidth: 280).background(.background.secondary)
            VStack(spacing: 0) {
                if let format = FormatCatalog.format(workspace.selectedID ?? "") {
                    FormatWorkspaceView(format: format, session: workspace.session(for: format.id), workspace: workspace)
                        .id(format.id)
                } else {
                    ContentUnavailableView("选择一种格式", systemImage: "sidebar.left", description: Text("同一格式的动作共用草稿。"))
                }
                if let message = workspace.storageMessage {
                    Text(message).font(.caption).foregroundStyle(.red).padding(12)
                }
            }.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity).background(.background)
        }.frame(minWidth: 800, minHeight: 600)
            .navigationTitle("OhMyBoop")
            .onChange(of: workspace.selectedID, initial: true) {
                if FormatCatalog.format(workspace.selectedID ?? "")?.isOther == true { otherExpanded = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in workspace.save() }
    }
}

private struct FormatSearchResults: View {
    let query: String
    let workspace: Workspace
    var body: some View {
        let matches = FormatCatalog.search(query, tools: workspace.tools)
        if matches.isEmpty {
            ContentUnavailableView("没有匹配的格式或动作", systemImage: "magnifyingglass", description: Text("试试 JSON、格式化或去反斜杠。"))
        } else {
            List(matches) { match in
                Button { workspace.reveal(match) } label: {
                    Label(match.title, systemImage: match.format.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }.buttonStyle(.plain).help("定位到工作区，不自动执行")
            }.listStyle(.sidebar)
        }
    }
}

private struct FormatWorkspaceView: View {
    let format: ContentFormat
    @Bindable var session: EditorSession
    let workspace: Workspace
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: format.symbol).font(.system(size: 24)).foregroundStyle(.mint)
                    .frame(width: 48, height: 48).background(.mint.opacity(0.1), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.title).font(.title2.weight(.semibold))
                    Text("一份草稿，连续处理").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if !(workspace.archivedDrafts[format.id] ?? []).isEmpty {
                    Button("历史草稿", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                        .disabled(session.isRunning)
                }
            }.padding(24)
            Divider()
            ActionToolbar(format: format, session: session, workspace: workspace)
                .padding(.horizontal, 20).padding(.vertical, 10)
            if let action = format.actions.first(where: { $0.id == workspace.revealedActionID }) {
                HStack {
                    Text("已定位：\(action.title)").font(.caption)
                    Text(session.scope(for: action)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ActionButton(action: action, session: session)
                    Button("收起") { workspace.revealedActionID = nil }.buttonStyle(.borderless)
                }.padding(.horizontal, 24).padding(.bottom, 10)
            }
            Divider()
            EditorControls(session: session)
            Divider()
            VSplitView {
                PersistentEditor(session: session)
                    .overlay(alignment: .topLeading) {
                        if session.text.isEmpty {
                            Text("在这里输入或粘贴文本…\n\n此格式的动作共用这份草稿。")
                                .font(.system(size: 14, design: .monospaced)).foregroundStyle(.tertiary)
                                .padding(.leading, 29).padding(.top, 24).allowsHitTesting(false)
                        }
                    }.frame(minHeight: 160, maxHeight: .infinity)
                if let preview = session.preview {
                    ConversionPreview(session: preview, title: session.previewTitle ?? "结果", close: session.closePreview)
                        .id(preview.id)
                        .frame(minHeight: 130, idealHeight: 200, maxHeight: 300)
                }
            }
            Divider()
            EditorStatus(session: session)
        }.sheet(isPresented: $showingHistory) { DraftHistoryView(format: format, workspace: workspace) }
    }
}

private struct ActionButton: View {
    let action: ToolAction
    let session: EditorSession
    var body: some View {
        Button(action.title) { session.run(action) }
            .disabled(session.isRunning)
            .help(action.title + " · " + session.scope(for: action))
            .accessibilityIdentifier("action-" + action.id)
    }
}

private struct ActionToolbar: View {
    let format: ContentFormat
    let session: EditorSession
    let workspace: Workspace
    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(primary: format.primaryActions)
            bar(primary: Array(format.primaryActions.prefix(1)))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func bar(primary: [ToolAction]) -> some View {
        let shown = Set(primary.map(\.id))
        let conversions = format.actions.filter { $0.group == "转换" && !shown.contains($0.id) }
        return HStack(spacing: 8) {
            ForEach(primary) { action in
                ActionButton(action: action, session: session)
            }
            if !conversions.isEmpty {
                Menu("转换为") {
                    ForEach(conversions) { action in ActionButton(action: action, session: session) }
                }.fixedSize()
            }
            MoreActionsMenu(format: format, excluded: shown.union(conversions.map(\.id)), session: session, workspace: workspace)
        }.fixedSize(horizontal: true, vertical: false)
    }
}

private struct MoreActionsMenu: View {
    let format: ContentFormat
    let excluded: Set<String>
    let session: EditorSession
    let workspace: Workspace
    var body: some View {
        let remaining = format.actions.filter { !excluded.contains($0.id) }
        let groups = Array(Set(remaining.map(\.group))).sorted()
        let favorites = format.actions.filter { workspace.favorites.contains($0.id) }
        Menu("更多") {
            if !favorites.isEmpty {
                Section("已收藏动作") {
                    ForEach(favorites) { action in ActionButton(action: action, session: session) }
                }
            }
            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(remaining.filter { $0.group == group }) { action in
                        ActionButton(action: action, session: session)
                    }
                }
            }
            Menu("管理收藏") {
                ForEach(format.actions) { action in
                    Toggle(action.title, isOn: Binding(get: { workspace.favorites.contains(action.id) }, set: { value in
                        if workspace.favorites.contains(action.id) != value { workspace.toggleFavorite(action.id) }
                    }))
                }
            }
        }.fixedSize()
    }
}

private struct EditorControls: View {
    @Bindable var session: EditorSession
    var body: some View {
        HStack(spacing: 12) {
            Picker("高亮", selection: $session.highlightLanguage) {
                ForEach(HighlightLanguage.allCases) { language in Text(language.title).tag(language) }
            }.labelsHidden().frame(width: 110).accessibilityLabel("高亮语言").help(session.highlightStatus)
            Text(session.scope(for: session.lastAction)).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                if let value = NSPasteboard.general.string(forType: .string) { session.replaceText(value) }
            } label: { Image(systemName: "document.on.clipboard") }
                .help("粘贴并替换全文（可撤销）").disabled(session.isRunning)
            Button { copyText(session.text) } label: { Image(systemName: "doc.on.doc") }.help("复制全文")
            Button { session.replaceText("") } label: { Image(systemName: "trash") }
                .help("清空当前格式草稿（可撤销）").disabled(session.isRunning || session.text.isEmpty)
        }.buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 10)
    }
}

private struct ConversionPreview: View {
    let session: EditorSession
    let title: String
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("原文保留").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("复制结果") { copyText(session.text) }
                Button("关闭", systemImage: "xmark") { close() }.labelStyle(.iconOnly)
            }.padding(.horizontal, 20).padding(.vertical, 8)
            Divider()
            PersistentEditor(session: session)
        }.accessibilityIdentifier("conversion-preview")
    }
}

private struct EditorStatus: View {
    let session: EditorSession
    var body: some View {
        HStack(spacing: 12) {
            if session.isRunning {
                ProgressView().controlSize(.small)
                Text("正在处理…").font(.caption)
            } else if let message = session.message {
                Image(systemName: session.isError ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(session.isError ? .red : .mint)
                Text(message).font(.caption).textSelection(.enabled).lineLimit(2)
            } else {
                Text("\(session.characterCount) 字符 · \(session.lineCount) 行 · \(session.highlightStatus)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let action = session.lastAction {
                Text("⌘↩ \(action.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }
}

private struct DraftHistoryView: View {
    let format: ContentFormat
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(format.title) · 历史草稿").font(.title2)
            Text("恢复前会保留当前草稿，原归档也会保留。").font(.callout).foregroundStyle(.secondary)
            List(workspace.archivedDrafts[format.id] ?? []) { archive in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(FormatCatalog.action(archive.sourceID)?.title ?? archive.sourceID).font(.headline)
                        Text(archive.sourceID).font(.caption).foregroundStyle(.secondary)
                        Text(archive.draft.text.isEmpty ? "空草稿" : String(archive.draft.text.prefix(150))).font(.caption).lineLimit(3)
                    }
                    Spacer()
                    Button("恢复") { workspace.restoreArchive(archive, in: format.id); dismiss() }
                        .disabled(workspace.session(for: format.id).isRunning)
                }.padding(.vertical, 5)
            }
            HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(minWidth: 520, idealWidth: 640, minHeight: 400, idealHeight: 500)
    }
}

private func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
private struct PersistentEditor: NSViewRepresentable {
    let session: EditorSession
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let scroll = session.scrollView
        scroll.removeFromSuperview()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        DispatchQueue.main.async { session.restoreScroll() }
        return container
    }
    func updateNSView(_ view: NSView, context: Context) {}
    func makeCoordinator() -> EditorSession { session }
    static func dismantleNSView(_ view: NSView, coordinator: EditorSession) { coordinator.captureScroll() }
}
