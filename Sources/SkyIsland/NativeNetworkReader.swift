import Foundation
import Darwin
import IslandCore

final class NativeNetworkReader {
    private var accumulator = NetworkRateAccumulator()

    func read(at date: Date) throws -> NetworkRate? {
        do { return accumulator.consume(try counters(), at: date) }
        catch { accumulator.reset(); throw error }
    }

    func counters() throws -> [InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { throw readError() }
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes { buffer in sysctl(&mib, UInt32(mib.count), buffer.baseAddress, &size, nil, 0) }
            if result != 0 { if errno == ENOMEM { continue }; throw readError() }
            return data.withUnsafeBytes { buffer -> [InterfaceCounters] in
                var counters: [InterfaceCounters] = [], offset = 0
                while offset + 4 <= size {
                    let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                    guard length >= 4, offset + length <= size else { break }
                    if buffer[offset + 3] == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size {
                        let info = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                        var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                        if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                            let name = String(cString: nameBuffer)
                            // Physical Ethernet / Wi-Fi interfaces avoid counting VPN tunnels twice.
                            if name.hasPrefix("en"), info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_LOOPBACK == 0 {
                                counters.append(InterfaceCounters(identifier: "\(info.ifm_index):\(name)", received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes))
                            }
                        }
                    }
                    offset += length
                }
                return counters
            }
        }
        throw readError()
    }
    private func readError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "网络速率暂不可用"])
    }
}
