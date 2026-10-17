import SwiftUI
import IslandCore

struct KeepAwakeView: View {
    @ObservedObject var service: KeepAwakeService
    var accent: Color
    private let mint = Color(red: 0.36, green: 0.88, blue: 0.73)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("让任务，继续运行。").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                    Text("按你的节奏，让 Mac 保持唤醒。").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 22, weight: .light))
                    .foregroundStyle(service.isActive ? mint : accent.opacity(0.6))
            }
            HStack(spacing: 10) {
                ForEach(KeepAwakeMode.allCases, id: \.self) { mode in modeCard(mode) }
            }
            HStack(spacing: 12) {
                Label("持续时间", systemImage: "clock").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                Picker("持续时间", selection: $service.selectedDuration) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in Text(duration.label).tag(duration) }
                }.labelsHidden().pickerStyle(.segmented).controlSize(.small).font(.system(size: 10))
            }.frame(height: 30)
            sessionCard
            HStack(spacing: 8) {
                Button { service.start() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: service.isActive ? "arrow.clockwise" : "power")
                        Text(service.isActive ? "应用设置" : "开始防休眠")
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 35).background(accent, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(IslandPressStyle()).disabled(service.isPreview)
                    .help("按 F13 可直接开启或结束防休眠，无需展开界面。")
                if service.isActive {
                    Button { service.stop() } label: {
                        Text("结束").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 72, height: 35).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(IslandPressStyle()).disabled(service.isPreview)
                    if service.session?.mode == .background {
                        Button { service.sleepDisplay() } label: {
                            Label("立即关屏", systemImage: "display").font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8)).frame(width: 105, height: 35)
                                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(IslandPressStyle()).disabled(service.isPreview)
                            .help("只关闭显示器；后台防休眠继续生效。移动鼠标可唤醒显示器。")
                    }
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: service.message == nil ? "info.circle" : "exclamationmark.circle").font(.system(size: 10))
                Text(service.message ?? (service.isPreview ? "界面预览 · 未创建防休眠请求" : "防止自动休眠，后台网络与磁盘可继续使用。\n合盖、手动睡眠和低电量睡眠仍遵循 macOS 行为。"))
                    .font(.system(size: 9)).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
            }.foregroundStyle(service.message == nil ? .white.opacity(0.32) : .orange.opacity(0.8))
        }
    }

    private func modeCard(_ mode: KeepAwakeMode) -> some View {
        Button { service.selectedMode = mode } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: mode == .display ? "sun.max" : "moon.stars").font(.system(size: 14))
                        .foregroundStyle(service.selectedMode == mode ? accent : .white.opacity(0.5))
                    Text(mode.title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: service.selectedMode == mode ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12)).foregroundStyle(service.selectedMode == mode ? accent : .white.opacity(0.15))
                }
                Text(mode.description).font(.system(size: 10)).lineSpacing(3).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Text(mode.command).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(service.selectedMode == mode ? accent.opacity(0.065) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(service.selectedMode == mode ? accent.opacity(0.4) : .white.opacity(0.05), lineWidth: 0.8))
        }.buttonStyle(IslandPressStyle()).accessibilityLabel("\(mode.title)，\(mode.description)")
            .accessibilityValue(service.selectedMode == mode ? "已选择" : "未选择")
    }

    private var sessionCard: some View {
        HStack(spacing: 10) {
            Circle().fill(service.isActive ? mint : .white.opacity(0.2)).frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 5) {
                Text(service.session.map { "正在\($0.mode == .display ? "保持显示器常亮" : "后台运行")" } ?? "尚未开启")
                    .font(.system(size: 11, weight: .medium))
                Text(service.session?.mode.command ?? "选择模式和时长后开始。")
                    .font(.system(size: 9, design: service.isActive ? .monospaced : .default)).foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            if let session = service.session {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(session.remaining(at: context.date).map { MediaTrack.timeLabel($0) } ?? "不限时")
                            .font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(mint)
                        Text(session.expiresAt == nil ? "直到手动结束" : "剩余时间").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3))
                    }
                }
            } else { Image(systemName: "power").font(.system(size: 17, weight: .light)).foregroundStyle(.white.opacity(0.18)) }
        }.padding(13).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
