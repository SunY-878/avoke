import SwiftUI

struct IslandSettingsView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var media: MediaService
    @ObservedObject var clipboard: ClipboardService
    var accent: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline) {
                    Text("你的岛，你的节奏。").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                    Spacer()
                    Text("SKY ISLAND  /  1.2").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(.white.opacity(0.25))
                }.padding(.bottom, 3)
                section("外观与交互") {
                    HStack {
                        Label("点缀色", systemImage: "paintpalette").font(.system(size: 11))
                        Spacer()
                        ForEach(Accent.allCases, id: \.self) { value in
                            Button { preferences.accent = value } label: {
                                Circle().fill(Color(nsColor: value.color)).frame(width: 15, height: 15)
                                    .padding(3).overlay(Circle().stroke(preferences.accent == value ? .white.opacity(0.8) : .clear, lineWidth: 1))
                            }.buttonStyle(IslandPressStyle()).help(value.label).accessibilityLabel(value.label)
                        }
                    }.frame(height: 28)
                    settingsSlider("岛体大小", symbol: "arrow.up.left.and.arrow.down.right", value: $preferences.islandScale, range: 0.85...1.15, label: "\(Int(preferences.islandScale * 100))%")
                    settingsSlider("悬停延迟", symbol: "cursorarrow", value: $preferences.hoverDelay, range: 0.05...0.6, label: "\(Int(preferences.hoverDelay * 1000)) ms")
                    settingsSlider("顶部距离", symbol: "rectangle.topthird.inset.filled", value: $preferences.topOffset, range: 0...70, label: "\(Int(preferences.topOffset)) pt")
                    HStack {
                        Label("显示器", systemImage: "display").font(.system(size: 11)); Spacer()
                        Picker("显示器", selection: $preferences.displayID) {
                            Text("主显示器").tag("")
                            ForEach(model.displayNames, id: \.id) { display in Text(display.name).tag(display.id) }
                        }.labelsHidden().font(.system(size: 10)).frame(maxWidth: 175)
                    }.frame(height: 28)
                }
                section("剪贴板") {
                    toggle("暂停记录", symbol: "pause.circle", binding: $preferences.capturePaused)
                    toggle("重启后保留历史", symbol: "internaldrive", binding: $preferences.persistHistory)
                    HStack {
                        Label("历史容量", systemImage: "clock.arrow.circlepath").font(.system(size: 11)); Spacer()
                        Picker("历史容量", selection: $preferences.historyLimit) {
                            Text("50 条").tag(50); Text("100 条").tag(100); Text("200 条").tag(200)
                        }.labelsHidden().font(.system(size: 10)).frame(width: 110)
                    }.frame(height: 28)
                    Text("内容仅存于本机；自动跳过被来源应用标记为敏感的剪贴板。图片会缩放到适合预览的尺寸。")
                        .font(.system(size: 9)).lineSpacing(4).foregroundStyle(.white.opacity(0.3))
                }
                section("日常") {
                    toggle("轻触反馈", symbol: "hand.tap", binding: $preferences.haptics)
                    toggle("登录时启动", symbol: "power", binding: Binding(get: { model.launchAtLogin }, set: { model.onLoginChange?($0) }))
                    HStack {
                        Label("呼出 / 收起", systemImage: "keyboard").font(.system(size: 11)); Spacer()
                        Text("⌥ Space").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                    }.frame(height: 28)
                }
                HStack(spacing: 12) {
                    Button { media.reconnect() } label: { Label("重新连接媒体", systemImage: "arrow.clockwise").font(.system(size: 10)) }
                    Spacer()
                    Button {
                        let enabled = !media.isDemo
                        media.setDemo(enabled); clipboard.setDemo(enabled)
                        model.selectedTab = .music
                    } label: { Label(media.isDemo ? "结束演示" : "体验演示", systemImage: "sparkles").font(.system(size: 10)) }
                }.buttonStyle(IslandPressStyle()).foregroundStyle(accent)
                if let message = model.settingsMessage ?? media.connectionIssue ?? clipboard.storageIssue {
                    Text(message).font(.system(size: 10)).foregroundStyle(.orange.opacity(0.85))
                }
                Text("悬停展开，移开收起。点击图钉可固定；Esc 随时收起。")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3)).padding(.bottom, 4)
            }
        }.scrollIndicators(.hidden)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.white.opacity(0.3))
            VStack(spacing: 5, content: content).padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        }
    }
    private func toggle(_ label: String, symbol: String, binding: Binding<Bool>) -> some View {
        HStack {
            Label(label, systemImage: symbol).font(.system(size: 11))
            Spacer()
            Toggle(label, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }.frame(height: 27)
    }
    private func settingsSlider(_ label: String, symbol: String, value: Binding<Double>, range: ClosedRange<Double>, label display: String) -> some View {
        HStack(spacing: 10) {
            Label(label, systemImage: symbol).font(.system(size: 11)).frame(width: 108, alignment: .leading)
            Slider(value: value, in: range).controlSize(.mini)
            Text(display).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.4)).frame(width: 48, alignment: .trailing)
        }.frame(height: 27)
    }
}
