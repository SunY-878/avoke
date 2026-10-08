import SwiftUI
import AppKit
import IslandCore

private let secondary = Color.white.opacity(0.48)
private let muted = Color.white.opacity(0.28)

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var media: MediaService
    @ObservedObject var clipboard: ClipboardService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.82) }
    private var accent: Color { Color(nsColor: preferences.accent.color) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(attached: model.attached, expanded: model.expanded)
                    .fill(Color(red: 0.026, green: 0.028, blue: 0.036))
                if model.expanded && model.selectedTab == .music && media.track != nil {
                    RadialGradient(colors: [Color(nsColor: media.tint).opacity(0.075), .clear],
                                   center: UnitPoint(x: 0.15, y: 0.44), startRadius: 0, endRadius: 240)
                        .allowsHitTesting(false)
                }
                if model.expanded {
                    expandedBody
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                } else {
                    compactBody
                        .transition(.opacity)
                }
            }
            .frame(width: model.baseWidth, height: model.baseHeight, alignment: .top)
            .overlay {
                IslandShape(attached: model.attached, expanded: model.expanded)
                    .stroke(LinearGradient(colors: [.white.opacity(model.expanded ? 0.16 : 0.08), .white.opacity(0.015)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
            .clipShape(IslandShape(attached: model.attached, expanded: model.expanded))
            .shadow(color: .black.opacity(model.expanded ? 0.42 : 0.22), radius: model.expanded ? 22 : 7, y: 10)
            .scaleEffect(model.effectiveScale, anchor: .top)
            .frame(width: model.width, height: model.height, alignment: .top)
            .animation(animation, value: model.expanded)
            .animation(animation, value: model.selectedTab)
            .animation(animation, value: media.track != nil)
            .animation(animation, value: preferences.islandScale)
            .animation(animation, value: model.awake.isActive)
            .animation(animation, value: model.system.connectionNotice)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .tint(accent)
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            if let notice = model.system.connectionNotice {
                Image(systemName: notice.isDisconnected ? "wifi.slash" : "wifi").font(.system(size: 15))
                    .foregroundStyle(notice.isDisconnected ? .orange : .mint)
                if !model.attached { Text(notice.text).font(.system(size: 11, weight: .medium)) }
                Spacer(minLength: model.attached ? model.notchWidth : 4)
                if model.attached { Text(notice.isDisconnected ? "离线" : "恢复").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) }
                else { Circle().fill(notice.isDisconnected ? Color.orange : .mint).frame(width: 4, height: 4) }
            } else if let track = media.track {
                ArtworkView(image: media.artwork, tint: Color(nsColor: media.tint), size: 25)
                if !model.attached {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(track.artist.isEmpty ? media.playerName : track.artist).font(.system(size: 9)).foregroundStyle(secondary).lineLimit(1)
                    }
                } else {
                    Text(track.title).font(.system(size: 9, weight: .medium)).lineLimit(1).frame(width: 42)
                }
                Spacer(minLength: model.attached ? model.notchWidth + 4 : 4)
                EqualizerView(playing: track.isPlaying, color: Color(nsColor: media.tint), size: 22)
                if model.awake.isActive {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 10)).foregroundStyle(.mint).help(model.awake.session?.mode.title ?? "保持唤醒")
                } else if model.attached { Image(systemName: "clipboard").font(.system(size: 11)).foregroundStyle(secondary) }
            } else {
                Image(systemName: model.awake.isActive ? "cup.and.saucer.fill" : "sparkle").font(.system(size: 14, weight: .medium)).foregroundStyle(model.awake.isActive ? .mint : accent)
                if !model.attached {
                    if let session = model.awake.session {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.mode.title).font(.system(size: 11, weight: .medium))
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(session.remaining(at: context.date).map { MediaTrack.timeLabel($0) } ?? "直到手动结束")
                                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(secondary)
                            }
                        }
                    } else { Text("Sky Island").font(.system(size: 12, weight: .medium)).tracking(0.2) }
                }
                Spacer(minLength: model.attached ? model.notchWidth : 4)
                Circle().fill(model.awake.isActive ? .mint : (preferences.capturePaused ? muted : accent)).frame(width: 4, height: 4)
                if !model.attached { Image(systemName: "clipboard").font(.system(size: 11)).foregroundStyle(secondary) }
            }
        }
        .padding(.horizontal, model.attached ? 16 : 13)
        .frame(height: model.baseHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.open(tab: model.system.connectionNotice != nil ? .system : nil) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compactAccessibilityLabel)
    }

    private var compactAccessibilityLabel: String {
        if let notice = model.system.connectionNotice { return "\(notice.text)，点击查看网络状态" }
        if let track = media.track { return "\(track.title)，\(track.artist)。点击展开灵动岛" }
        if let session = model.awake.session { return "\(session.mode.title)，防休眠已开启。点击查看详情" }
        return "Sky Island，点击查看剪贴板"
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.top, 12).padding(.bottom, 18)
            Group {
                switch model.selectedTab {
                case .music: MusicDetailView(media: media, accent: accent)
                case .clipboard: ClipboardHistoryView(clipboard: clipboard, preferences: preferences, accent: accent)
                case .system: SystemStatusView(service: model.system, accent: accent)
                case .awake: KeepAwakeView(service: model.awake, accent: accent)
                case .settings: IslandSettingsView(model: model, preferences: preferences, media: media, clipboard: clipboard, accent: accent)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .id(model.selectedTab)
            .transition(.opacity.combined(with: .offset(y: 5)))
        }
        .padding(.horizontal, 24)
        .padding(.top, model.topInset)
        .padding(.bottom, 18)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            tabButton(.music, title: "正在播放", symbol: "waveform")
            tabButton(.clipboard, title: "剪贴板", symbol: "clipboard", count: clipboard.entries.count)
            tabButton(.system, title: "系统", symbol: "cpu")
            tabButton(.awake, title: "唤醒", symbol: model.awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
            Spacer()
            if let notice = model.system.connectionNotice {
                IslandIconButton(symbol: notice.isDisconnected ? "wifi.slash" : "wifi", help: notice.text, active: true,
                                 accent: notice.isDisconnected ? .orange : .mint) { model.selectedTab = .system }
            } else if media.isDemo && model.selectedTab != .system && model.selectedTab != .awake {
                Text("演示").font(.system(size: 9, weight: .medium)).foregroundStyle(accent).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(accent.opacity(0.1), in: Capsule())
            }
            IslandIconButton(symbol: model.pinned ? "pin.fill" : "pin", help: model.pinned ? "取消固定" : "固定展开", active: model.pinned, accent: accent) {
                model.pinned.toggle()
            }
            IslandIconButton(symbol: "slider.horizontal.3", help: "设置", active: model.selectedTab == .settings, accent: accent) {
                model.selectedTab = model.selectedTab == .settings ? (media.track == nil ? .clipboard : .music) : .settings
            }
            IslandIconButton(symbol: "xmark", help: "收起 · Esc", accent: accent) { model.close() }
        }
        .frame(height: 30)
    }

    private func tabButton(_ tab: IslandTab, title: String, symbol: String, count: Int? = nil) -> some View {
        Button { model.selectedTab = tab } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
                if let count, count > 0 { Text("\(count)").font(.system(size: 9, weight: .medium)).foregroundStyle(model.selectedTab == tab ? accent : muted) }
            }
            .foregroundStyle(model.selectedTab == tab ? .white : secondary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(model.selectedTab == tab ? Color.white.opacity(0.075) : .clear, in: Capsule())
        }
        .buttonStyle(IslandPressStyle())
    }
}

struct IslandShape: Shape {
    var attached: Bool
    var expanded: Bool
    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: expanded ? 28 : rect.height / 2) }
        let top: CGFloat = expanded ? 11 : 7, bottom: CGFloat = expanded ? 30 : 15
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: top, y: top), control: CGPoint(x: top, y: 0))
        path.addLine(to: CGPoint(x: top, y: rect.height - bottom))
        path.addQuadCurve(to: CGPoint(x: top + bottom, y: rect.height), control: CGPoint(x: top, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - top - bottom, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: rect.width - top, y: rect.height - bottom), control: CGPoint(x: rect.width - top, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - top, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.width - top, y: 0))
        path.closeSubpath(); return path
    }
}

struct IslandPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct IslandIconButton: View {
    var symbol: String
    var help: String
    var active = false
    var accent: Color = .blue
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? accent : (hovered ? .white : secondary))
                .frame(width: 27, height: 27)
                .background(hovered || active ? .white.opacity(0.065) : .clear, in: Circle())
        }.buttonStyle(IslandPressStyle()).help(help).accessibilityLabel(help).onHover { hovered = $0 }
    }
}

struct ArtworkView: View {
    var image: NSImage?
    var tint: Color
    var size: CGFloat
    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else {
                LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.30, weight: .light)).foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.14).stroke(.white.opacity(0.12), lineWidth: 0.6))
        .accessibilityLabel("专辑封面")
    }
}

struct EqualizerView: View {
    var playing: Bool
    var color: Color
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !playing || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(color).frame(width: 2.8, height: barHeight(index: index, time: time))
                }
            }.frame(width: 20, height: size)
        }.accessibilityLabel(playing ? "正在播放" : "已暂停")
    }
    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard playing else { return size * 0.22 }
        let frequency = 5.0 + Double(index) * 0.8
        let wave = (sin(time * frequency + Double(index) * 1.6) + 1) / 2
        return size * CGFloat(0.22 + wave * 0.67)
    }
}

struct MusicDetailView: View {
    @ObservedObject var media: MediaService
    var accent: Color
    var body: some View {
        if let track = media.track {
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 20) {
                    ArtworkView(image: media.artwork, tint: Color(nsColor: media.tint), size: 108)
                        .shadow(color: Color(nsColor: media.tint).opacity(0.18), radius: 22, y: 6)
                        .id(track.identity)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(track.isPlaying ? Color(nsColor: media.tint) : secondary).frame(width: 4, height: 4)
                            Text(track.isPlaying ? "此刻的旋律" : "稍作停留").font(.system(size: 10, weight: .medium)).tracking(1.2).foregroundStyle(secondary)
                            Spacer(); EqualizerView(playing: track.isPlaying, color: Color(nsColor: media.tint), size: 15)
                        }
                        Text(track.title).font(.system(size: 20, weight: .semibold)).tracking(-0.5).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(track.artist.isEmpty ? media.playerName : track.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                        if !track.album.isEmpty { Text(track.album).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.animation(.easeInOut(duration: 0.28), value: track.identity)
                PlaybackProgress(media: media, track: track, color: Color(nsColor: media.tint))
                HStack {
                    Button { media.openPlayer() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 10))
                            Text(media.playerName).font(.system(size: 10)).lineLimit(1)
                        }.foregroundStyle(secondary).frame(maxWidth: 120, alignment: .leading)
                    }.buttonStyle(IslandPressStyle()).help("打开播放器")
                    Spacer(minLength: 10)
                    HStack(spacing: 22) {
                        Button { media.command(5) } label: { Image(systemName: "backward.end.fill").font(.system(size: 16)).frame(width: 28, height: 32) }
                            .disabled(track.prohibitsSkip).help("上一首").accessibilityLabel("上一首")
                        Button { media.command(2) } label: {
                            Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(.black).frame(width: 46, height: 46).background(.white, in: Circle())
                        }.help(track.isPlaying ? "暂停" : "播放").accessibilityLabel(track.isPlaying ? "暂停" : "播放")
                        Button { media.command(4) } label: { Image(systemName: "forward.end.fill").font(.system(size: 16)).frame(width: 28, height: 32) }
                            .disabled(track.prohibitsSkip).help("下一首").accessibilityLabel("下一首")
                    }.buttonStyle(IslandPressStyle())
                    Spacer(minLength: 10)
                    HStack(spacing: 5) {
                        Image(systemName: "hifispeaker.fill").font(.system(size: 11))
                        Text("系统音频").font(.system(size: 9))
                    }.foregroundStyle(muted).frame(width: 92, alignment: .trailing)
                }
                HStack {
                    Image(systemName: "sparkle").foregroundStyle(Color(nsColor: media.tint))
                    Text(media.connectionIssue ?? "让音乐，近一点。").foregroundStyle(muted).lineLimit(1)
                    Spacer()
                    Text(track.isPlaying ? "NOW PLAYING" : "PAUSED").tracking(1.5).foregroundStyle(muted)
                }.font(.system(size: 8, weight: .medium)).padding(.top, 2)
            }
        } else {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(accent.opacity(0.04)).frame(width: 82, height: 82)
                    Circle().stroke(accent.opacity(0.15), lineWidth: 0.7).frame(width: 64, height: 64)
                    Image(systemName: "waveform").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                }
                Text("好音乐，值得一个位置。 ").font(.system(size: 17, weight: .medium))
                Text(media.connectionIssue ?? "在音乐、Spotify 或浏览器中播放\n你的旋律会自动出现在这里。")
                    .font(.system(size: 11)).foregroundStyle(secondary).multilineTextAlignment(.center).lineSpacing(5)
                HStack(spacing: 8) {
                    Text("自动识别系统媒体").font(.system(size: 9)).foregroundStyle(muted)
                    Circle().fill(accent).frame(width: 4, height: 4)
                }.padding(.top, 8)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PlaybackProgress: View {
    @ObservedObject var media: MediaService
    var track: MediaTrack
    var color: Color
    @State private var dragging: Double?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = dragging ?? track.position(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { geometry in
                    let progress = track.duration > 0 ? max(0, min(1, elapsed / track.duration)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.10)).frame(height: 3)
                        Capsule().fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geometry.size.width * progress), height: 3)
                        if track.duration > 0 {
                            Circle().fill(.white).frame(width: dragging == nil ? 5 : 8, height: dragging == nil ? 5 : 8)
                                .offset(x: max(0, min(geometry.size.width - 5, geometry.size.width * progress - 2.5)))
                        }
                    }.frame(maxHeight: .infinity).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard track.duration > 0 else { return }
                            dragging = min(1, max(0, value.location.x / max(1, geometry.size.width))) * track.duration
                        }.onEnded { _ in
                            if let dragging { media.seek(to: dragging) }; dragging = nil
                        })
                }.frame(height: 16)
                HStack {
                    Text(MediaTrack.timeLabel(elapsed)); Spacer()
                    Text(track.duration > 0 ? "−" + MediaTrack.timeLabel(max(0, track.duration - elapsed)) : "LIVE")
                }.font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(MediaTrack.timeLabel(elapsed)) / \(MediaTrack.timeLabel(track.duration))")
            .accessibilityAdjustableAction { direction in
                media.seek(to: elapsed + (direction == .increment ? 10 : -10))
            }
        }
    }
}
