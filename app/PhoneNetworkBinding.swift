import Darwin
import Foundation
import SystemConfiguration

/// Identity of the local endpoint, independent of default internet routes and VPN paths.
struct PhoneNetworkBinding: Equatable, Sendable, Identifiable {
    let interfaceName: String
    let address: String
    let netmask: String

    var id: String { interfaceName + ":" + address }
    var title: String { interfaceName + " · " + address }

    static func isPrivateIPv4(_ address: String) -> Bool {
        let octets = address.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        return octets.count == 4 && (octets[0] == 10 ||
            (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
    }

    static func available() -> [Self] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(first) }
        let physical = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        var wifi = Set<String>()
        var lan = Set<String>()
        for interface in physical {
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) else { continue }
            if type == kSCNetworkInterfaceTypeIEEE80211 { wifi.insert(name); lan.insert(name) }
            if type == kSCNetworkInterfaceTypeEthernet { lan.insert(name) }
        }
        var bindings: [Self] = []
        var item: UnsafeMutablePointer<ifaddrs>? = first
        while let current = item {
            item = current.pointee.ifa_next
            let entry = current.pointee
            let name = String(cString: entry.ifa_name)
            guard lan.contains(name), let raw = entry.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET) else { continue }
            var numeric = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(raw, socklen_t(raw.pointee.sa_len), &numeric, socklen_t(numeric.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(decoding: numeric.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if isPrivateIPv4(address), let binding = Self.current(address: address), !bindings.contains(binding) {
                bindings.append(binding)
            }
        }
        return bindings.sorted {
            if wifi.contains($0.interfaceName) != wifi.contains($1.interfaceName) { return wifi.contains($0.interfaceName) }
            return $0.id < $1.id
        }
    }

    static func current(address: String) -> Self? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(first) }
        func numeric(_ raw: UnsafePointer<sockaddr>?) -> String? {
            guard let raw, raw.pointee.sa_family == UInt8(AF_INET) else { return nil }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(raw, socklen_t(raw.pointee.sa_len), &buffer, socklen_t(buffer.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        var item: UnsafeMutablePointer<ifaddrs>? = first
        while let current = item {
            item = current.pointee.ifa_next
            let entry = current.pointee
            guard entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  numeric(entry.ifa_addr) == address, let mask = numeric(entry.ifa_netmask) else { continue }
            return Self(interfaceName: String(cString: entry.ifa_name), address: address, netmask: mask)
        }
        return nil
    }

    func contains(_ peer: String) -> Bool {
        func bytes(_ value: String) -> [UInt8] {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return [] }
            return parts.compactMap { UInt8($0) }
        }
        let remote = bytes(peer), local = bytes(address), mask = bytes(netmask)
        guard remote.count == 4, local.count == 4, mask.count == 4, mask.contains(where: { $0 != 0 }) else { return false }
        return (0..<4).allSatisfy { remote[$0] & mask[$0] == local[$0] & mask[$0] }
    }
}
