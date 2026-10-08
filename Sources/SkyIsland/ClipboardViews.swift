import SwiftUI
import IslandCore

private enum ClipboardFilter: String, CaseIterable {
    case all = "全部", text = "文本", link = "链接", image = "图片", pinned = "置顶"
    func includes(_ entry: ClipboardEntry) -> Bool {
        switch self {
        case .all: true
        case .text: entry.kind == .text
        case .link: entry.kind == .link
        case .image: entry.kind == .image
        case .pinned: entry.isPinned
        }
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var preferences: Preferences
    var accent: Color
    @State private var query = ""
    @State private var filter = ClipboardFilter.all
    @State private var preview: ClipboardEntry?
    @State private var showClear = false
    @FocusState private var searchFocused: Bool
    private var filtered: [ClipboardEntry] { clipboard.entries.filter { filter.includes($0) && $0.matches(query) } }

    var body: some View {
        VStack(spacing: 12) {
            if let preview {
                previewContent(preview)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    TextField("搜索内容或来源", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                        .focused($searchFocused).accessibilityLabel("搜索剪贴板历史")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.35)) }
                            .buttonStyle(.plain).accessibilityLabel("清除搜索")
                    } else { Text("⌘ F").font(.system(size: 10)).foregroundStyle(.white.opacity(0.24)) }
                }.padding(.horizontal, 12).frame(height: 34).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .trailing) {
                        Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).frame(width: 0, height: 0).opacity(0)
                    }
                HStack(spacing: 5) {
                    ForEach(ClipboardFilter.allCases, id: \.self) { value in
                        Button { filter = value } label: {
                            Text(value.rawValue).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(filter == value ? accent : .white.opacity(0.4))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(filter == value ? accent.opacity(0.10) : .clear, in: Capsule())
                        }.buttonStyle(IslandPressStyle())
                    }
                    Spacer()
                    IslandIconButton(symbol: preferences.capturePaused ? "play.circle" : "pause.circle", help: preferences.capturePaused ? "继续记录" : "暂停记录", active: preferences.capturePaused, accent: accent) {
                        preferences.capturePaused.toggle()
                    }
                }
                if filtered.isEmpty {
                    VStack(spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13).stroke(accent.opacity(0.15), lineWidth: 0.8).frame(width: 42, height: 50).rotationEffect(.degrees(-10)).offset(x: -6)
                            RoundedRectangle(cornerRadius: 13).fill(Color(red: 0.06, green: 0.07, blue: 0.09)).frame(width: 42, height: 50).offset(x: 5)
                            Image(systemName: "clipboard").font(.system(size: 22, weight: .light)).foregroundStyle(accent).offset(x: 5)
                        }.frame(height: 62)
                        Text(query.isEmpty && filter == .all ? "每次复制，都有回声。" : "没有找到这段内容")
                            .font(.system(size: 15, weight: .medium))
                        Text(preferences.capturePaused ? "记录已暂停，点击右上角继续。" : (clipboard.entries.isEmpty ? "复制文字、链接、图片或文件\n下次需要时，来这里找。" : "换一个关键词或分类试试。"))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center).lineSpacing(5)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(filtered) { entry in
                                ClipboardRow(entry: entry, copied: clipboard.copiedID == entry.id, accent: accent,
                                             copy: { clipboard.copy(entry) }, pin: { clipboard.pin(entry.id) },
                                             delete: { clipboard.delete(entry.id) }, preview: { preview = entry })
                            }
                        }.padding(.vertical, 2)
                    }.scrollIndicators(.hidden)
                }
            }
            footer
        }
        .alert("清空剪贴板历史？", isPresented: $showClear) {
            Button("清空历史", role: .destructive) { clipboard.clear() }
            Button("取消", role: .cancel) {}
        } message: { Text("将删除所有历史记录，包括置顶内容。系统剪贴板中的内容会保留。") }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield").font(.system(size: 9))
            Text(clipboard.storageIssue ?? (preferences.capturePaused ? "记录已暂停" : "只在这台 Mac 上保存"))
                .font(.system(size: 9)).lineLimit(1)
            Spacer()
            if !clipboard.entries.isEmpty {
                Text("\(clipboard.entries.count) 条").font(.system(size: 9, design: .monospaced))
                Button { showClear = true } label: { Image(systemName: "trash").font(.system(size: 10)).frame(width: 24, height: 24) }
                    .buttonStyle(IslandPressStyle()).help("清空历史").accessibilityLabel("清空历史")
            }
        }.foregroundStyle(.white.opacity(0.3)).padding(.top, 2)
    }

    private func previewContent(_ entry: ClipboardEntry) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { preview = nil } label: { Label("返回历史", systemImage: "chevron.left").font(.system(size: 11)) }.buttonStyle(IslandPressStyle())
                Spacer()
                Button { clipboard.copy(entry) } label: {
                    Label(clipboard.copiedID == entry.id ? "已复制" : "复制内容", systemImage: clipboard.copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11)).foregroundStyle(accent)
                }.buttonStyle(IslandPressStyle())
            }.foregroundStyle(.white.opacity(0.6))
            if entry.kind == .image, let data = entry.data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView {
                    Text(entry.kind == .files ? entry.fileURLs.joined(separator: "\n") : entry.text)
                        .font(.system(size: 12)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }.background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("来自 \(entry.source) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
        }
    }
}

private struct ClipboardRow: View {
    var entry: ClipboardEntry
    var copied: Bool
    var accent: Color
    var copy: () -> Void
    var pin: () -> Void
    var delete: () -> Void
    var preview: () -> Void
    @State private var hovered = false
    private var symbol: String {
        switch entry.kind { case .text: "text.alignleft"; case .link: "link"; case .image: "photo"; case .files: "doc" }
    }
    var body: some View {
        HStack(spacing: 11) {
            Button(action: copy) {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(accent.opacity(entry.kind == .link ? 0.1 : 0.06))
                        if entry.kind == .image, let data = entry.data, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFill().frame(width: 35, height: 35).clipped()
                        } else { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(entry.kind == .link ? accent : .white.opacity(0.5)) }
                    }.frame(width: 35, height: 35).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(copied ? "已复制到剪贴板" : entry.title).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copied ? accent : .white.opacity(0.86)).lineLimit(1)
                        HStack(spacing: 4) {
                            if entry.isPinned { Image(systemName: "pin.fill").font(.system(size: 7)).foregroundStyle(accent) }
                            Text(entry.source)
                            Text("·")
                            Text(entry.date, style: .relative)
                        }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.32)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(IslandPressStyle()).help("点击复制 · 右键查看更多").accessibilityLabel("复制：\(entry.title)")
            if hovered || copied {
                if copied {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent).frame(width: 24)
                } else {
                    IslandIconButton(symbol: "eye", help: "预览内容", accent: accent, action: preview)
                    IslandIconButton(symbol: entry.isPinned ? "pin.fill" : "pin", help: entry.isPinned ? "取消置顶" : "置顶", active: entry.isPinned, accent: accent, action: pin)
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(copied ? accent.opacity(0.08) : .white.opacity(hovered ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(copied ? accent.opacity(0.2) : .clear, lineWidth: 0.6))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc", action: copy)
            Button("预览", systemImage: "eye", action: preview)
            Button(entry.isPinned ? "取消置顶" : "置顶", systemImage: "pin", action: pin)
            Divider()
            Button("删除", systemImage: "trash", role: .destructive, action: delete)
        }
    }
}
