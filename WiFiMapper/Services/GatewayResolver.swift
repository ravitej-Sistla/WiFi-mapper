import Darwin
import Foundation

/// Finds the router to probe. iOS doesn't expose the routing table to apps, so this
/// assumes the router is the first host of the Wi-Fi subnet (e.g. 192.168.4.1), which
/// holds for most mesh systems. Users can override it in Settings.
enum GatewayResolver {
    static func guessedGateway() -> String? {
        guard let (address, netmask) = wifiIPv4() else { return nil }
        let gateway = (address & netmask) &+ 1
        return [24, 16, 8, 0].map { String((gateway >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }

    /// The Wi-Fi interface's IPv4 address and netmask, in host byte order.
    static func wifiIPv4() -> (UInt32, UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard String(cString: entry.ifa_name) == "en0",
                  let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = entry.ifa_netmask else { continue }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            return (UInt32(bigEndian: address), UInt32(bigEndian: netmask))
        }
        return nil
    }
}
