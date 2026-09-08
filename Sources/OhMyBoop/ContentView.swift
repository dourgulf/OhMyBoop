// Created by lidawen.
import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var search = ""
    @State private var onlyFavorites = false

    private var filtered: [Tool] {
        workspace.tools.filter {
            (!onlyFavorites || workspace.favorites.contains($0.id)) &&
            (search.isEmpty || "\($0.name) \($0.description) \($0.tags) \($0.category)".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill")
                        .font(.title2).foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OhMyBoop").font(.headline)
                        Text("你的开发工具箱").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索功能…", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).help("清除搜索")
                    }
                }.padding(9).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    .padding(.horizontal, 14)
                Picker("功能范围", selection: $onlyFavorites) {
                    Text("全部功能").tag(false)
                    Text("收藏").tag(true)
                }.pickerStyle(.segmented).padding(14)
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "暂无收藏" : "没有匹配的功能", systemImage: search.isEmpty ? "star" : "magnifyingglass", description: Text(search.isEmpty ? "点击功能右上方的星标添加收藏。" : "试试 JSON、Base64 或分类名称。"))
                } else {
                    List(selection: $workspace.selectedID) {
                        ForEach(Catalog.categories, id: \.self) { category in
                            let items = filtered.filter { $0.category == category }
                            if !items.isEmpty {
                                Section(category) {
                                    ForEach(items) { tool in
                                        HStack(spacing: 10) {
                                            Image(systemName: tool.symbol).foregroundStyle(.secondary).frame(width: 20)
                                            Text(tool.name).lineLimit(1)
                                            Spacer(minLength: 2)
                                            if workspace.favorites.contains(tool.id) {
                                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                                            }
                                        }.padding(.vertical, 5).tag(tool.id)
                                    }
                                }
                            }
                        }
                    }.listStyle(.sidebar)
                }
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Circle().fill(.mint).frame(width: 6, height: 6)
                    Text("\(workspace.tools.count) 个功能 · 本地处理")
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary).padding(14)
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            .background(.background.secondary)
            VStack(spacing: 0) {
                if let tool = workspace.tools.first(where: { $0.id == workspace.selectedID }) {
                    ToolDetail(tool: tool, session: workspace.session(for: tool.id), workspace: workspace)
                        .id(tool.id)
                } else {
                    ContentUnavailableView("选择一个功能", systemImage: "sidebar.left", description: Text("从左侧工具列表开始。每个功能拥有独立草稿。"))
                }
                if let message = workspace.storageMessage {
                    Text(message).font(.caption).foregroundStyle(.red).padding(12)
                }
            }.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .frame(minWidth: 800, minHeight: 520)
        .navigationTitle("OhMyBoop")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in workspace.save() }
    }
}

private struct ToolDetail: View {
    let tool: Tool
    let session: EditorSession
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 24)).foregroundStyle(.mint)
                    .frame(width: 48, height: 48)
                    .background(.mint.opacity(0.1), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(tool.name).font(.title2.weight(.semibold))
                    Text(tool.description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button { workspace.toggleFavorite(tool.id) } label: {
                    Image(systemName: workspace.favorites.contains(tool.id) ? "star.fill" : "star")
                        .foregroundStyle(workspace.favorites.contains(tool.id) ? .orange : .secondary)
                }.buttonStyle(.borderless).help("收藏 / 取消收藏")
            }.padding(24)
            Divider()
            HStack(spacing: 14) {
                Text("编辑区").font(.subheadline.weight(.medium))
                Text(["ASCIIToHex", "HexToASCII", "AndroidIOSStrings", "IOSAndroidStrings"].contains(tool.id) ? "此功能处理全文" : "选中文本时仅处理选区")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    if let value = NSPasteboard.general.string(forType: .string) { session.replaceText(value) }
                } label: { Image(systemName: "document.on.clipboard") }.help("粘贴并替换全文（可撤销）").disabled(session.isRunning)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }.help("复制全文")
                Button { session.replaceText("") } label: { Image(systemName: "trash") }
                    .help("清空当前功能（可撤销）").disabled(session.isRunning || session.text.isEmpty)
            }.buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            ZStack(alignment: .topLeading) {
                PersistentEditor(session: session)
                if session.text.isEmpty {
                    Text("在这里输入或粘贴文本…\n\n此功能的草稿会独立保留。")
                        .font(.system(size: 14, design: .monospaced)).foregroundStyle(.tertiary)
                        .padding(.leading, 29).padding(.top, 24).allowsHitTesting(false)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                if session.isRunning {
                    ProgressView().controlSize(.small)
                    Text("正在处理…").font(.caption)
                } else if let message = session.message {
                    Image(systemName: session.isError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(session.isError ? .red : .mint)
                    Text(message).font(.caption).textSelection(.enabled).lineLimit(3)
                } else {
                    Text("\(session.characterCount) 字符 · \(session.lineCount) 行")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { session.run() } label: {
                    Label("执行", systemImage: "play.fill").padding(.horizontal, 10).padding(.vertical, 4)
                }.buttonStyle(.borderedProminent).tint(.accentColor)
                    .keyboardShortcut(.return, modifiers: .command).disabled(session.isRunning)
                    .help("执行当前功能 ⌘↩")
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
    }
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
