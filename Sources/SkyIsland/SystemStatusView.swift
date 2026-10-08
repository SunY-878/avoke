import SwiftUI
import Charts
import AppKit
import IslandCore

struct SystemStatusView: View {
    @ObservedObject var service: SystemStatusService
    var accent: Color
    private let mint = Color(red: 0.36, green: 0.88, blue: 0.73)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var snapshot: SystemSnapshot { service.snapshot }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("这台 Mac 的此刻。").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion) · \(service.processorCount) 逻辑核")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3)).lineLimit(1)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(service.isPreview ? accent : mint).frame(width: 4, height: 4)
                            Text(service.isPreview ? "PREVIEW" : "LIVE").font(.system(size: 8, weight: .medium)).tracking(1.2)
                        }.foregroundStyle(.white.opacity(0.4))
                    }
                    HStack(spacing: 10) {
                        metricCard(title: "CPU", symbol: "cpu", percentage: snapshot.cpu?.total, color: accent,
                        detail: snapshot.cpu.map { "用户 \(percent($0.user)) · 系统 \(percent($0.system))" } ?? "正在采样全系统 CPU",
                        history: service.cpuHistory)
                        metricCard(title: "内存", symbol: "memorychip", percentage: snapshot.memory?.percentage, color: mint,
                        detail: snapshot.memory.map { "\(bytes($0.used)) / \(bytes($0.total))" } ?? "正在读取物理内存",
                        history: service.memoryHistory)
                    }
                    networkCard
                    diskCard
                    HStack(spacing: 0) {
                        detailMetric("压缩内存", symbol: "arrow.down.right.and.arrow.up.left", value: snapshot.memory.map { bytes($0.compressed) } ?? "—")
                        detailDivider
                        detailMetric("交换内存", symbol: "arrow.left.arrow.right", value: snapshot.memory?.swap.map(bytes) ?? "—")
                        detailDivider
                        detailMetric("热状态", symbol: "thermometer.medium", value: snapshot.thermal.label, color: thermalColor)
                        detailDivider
                        detailMetric("运行时间", symbol: "clock", value: uptime(snapshot.uptime))
                    }.padding(.vertical, 12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                }.padding(.bottom, 2)
            }.scrollIndicators(.hidden)
            HStack(spacing: 5) {
                Image(systemName: snapshot.issues.isEmpty ? "waveform.path" : "exclamationmark.circle").font(.system(size: 9))
                Text(snapshot.issues.first ?? (service.isPreview ? "界面预览 · 演示数据" : "CPU / 内存 / 网络每秒更新"))
                .font(.system(size: 9)).lineLimit(1)
                Spacer()
                Button(action: openActivityMonitor) {
                    HStack(spacing: 4) {
                        Text("活动监视器").font(.system(size: 9))
                        Image(systemName: "arrow.up.right").font(.system(size: 8))
                    }.foregroundStyle(accent)
                }.buttonStyle(IslandPressStyle()).help("打开 macOS 活动监视器")
            }.foregroundStyle(snapshot.issues.isEmpty ? .white.opacity(0.3) : .orange.opacity(0.8))
        }
    }

    private func metricCard(title: String, symbol: String, percentage: Double?, color: Color, detail: String, history: MetricHistory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(title == "CPU" ? "全系统" : "物理内存").font(.system(size: 8)).foregroundStyle(.white.opacity(0.25))
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(percentage.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: percentage)
                if percentage != nil { Text("%").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.4)) }
            }
            Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.38)).lineLimit(1).minimumScaleFactor(0.8)
            MetricTrendView(history: history, color: color, title: title).frame(height: 28).padding(.top, 3)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(color.opacity(0.1), lineWidth: 0.7))
            .accessibilityElement(children: .combine)
    }

    private var networkCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "network").font(.system(size: 12)).foregroundStyle(accent)
                Text("网络").font(.system(size: 11, weight: .medium))
                Spacer()
                if !service.connection.transport.isEmpty {
                    Text(service.connection.transport).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                }
                Circle().fill(service.connection.state == .connected ? mint : (service.connection.state == .unknown ? .white.opacity(0.3) : .orange))
                    .frame(width: 4, height: 4)
                Text(service.connection.state.label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 12) {
                networkSpeed("下载", symbol: "arrow.down", value: snapshot.network?.download, color: mint)
                Rectangle().fill(.white.opacity(0.07)).frame(width: 1, height: 20)
                networkSpeed("上传", symbol: "arrow.up", value: snapshot.network?.upload, color: accent)
            }
        }.padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            .help("整机物理网卡吞吐，包含局域网流量；排除回环和 VPN 虚拟网卡以避免重复计数。已连接表示系统有可用网络路径，不代表互联网或远端服务一定可达。")
            .accessibilityElement(children: .combine)
    }
    private func networkSpeed(_ title: String, symbol: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                Text(DataRateFormat.label(value)).font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: value)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diskCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").font(.system(size: 13)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("磁盘空间").font(.system(size: 11, weight: .medium))
                    Text("用户目录所在磁盘").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(snapshot.disk.map { "\(bytes($0.available)) 可用" } ?? "—")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(snapshot.disk.map { "共 \(bytes($0.total)) · 已用 \(percent($0.percentage ?? 0))" } ?? "正在读取磁盘容量")
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.3))
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule().fill(LinearGradient(colors: [accent.opacity(0.4), accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * (snapshot.disk?.percentage ?? 0) / 100)
                }
            }.frame(height: 3)
        }.padding(13).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            .help("可用空间包含 macOS 可以清理的空间，每 15 秒更新。")
            .accessibilityElement(children: .combine)
    }

    private func detailMetric(_ title: String, symbol: String, value: String, color: Color = .white.opacity(0.75)) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 8))
                Text(title).font(.system(size: 8))
            }.foregroundStyle(.white.opacity(0.3))
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
    private var detailDivider: some View { Rectangle().fill(.white.opacity(0.07)).frame(width: 1, height: 22) }
    private var thermalColor: Color {
        switch snapshot.thermal { case .nominal: mint; case .fair: .yellow; case .serious: .orange; case .critical: .red; case .unknown: .white.opacity(0.4) }
    }
    private func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, value))), countStyle: .memory)
    }
    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
    private func uptime(_ value: TimeInterval) -> String {
        guard snapshot.sampledAt != nil else { return "—" }
        let hours = Int(max(0, value) / 3600)
        if hours >= 24 { return "\(hours / 24)天 \(hours % 24)时" }
        if hours > 0 { return "\(hours)时 \(Int(value / 60) % 60)分" }
        return "\(Int(max(0, value) / 60))分钟"
    }
    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

private struct MetricTrendView: View {
    var history: MetricHistory
    var color: Color
    var title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let end = history.points.last?.date ?? Date()
        Chart(history.points) { point in
            AreaMark(x: .value("时间", point.date), yStart: .value("基线", 0), yEnd: .value("占用率", point.value))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.2), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("时间", point.date), y: .value("占用率", point.value))
                .foregroundStyle(color.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            if point.id == history.points.last?.id {
                PointMark(x: .value("时间", point.date), y: .value("占用率", point.value)).foregroundStyle(color).symbolSize(8)
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-59)...end)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: history.points.last?.date)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近一分钟\(title)占用率趋势，范围 0 至 100%")
    }
}
