import Foundation

public enum DataRateFormat {
    public static func label(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return "—" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var scaled = value, index = 0
        while scaled >= 1000 && index < units.count - 1 { scaled /= 1000; index += 1 }
        return index == 0 ? String(format: "%.0f %@", scaled, units[index]) : String(format: "%.1f %@", scaled, units[index])
    }
}
