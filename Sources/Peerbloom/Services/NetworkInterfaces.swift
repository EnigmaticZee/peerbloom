import Darwin
import Foundation
import SystemConfiguration

struct NetworkInterface: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let addresses: [String]
    let isUp: Bool
    /// The name macOS shows for it, like "Wi-Fi" or "Ethernet". Nil for tunnels and virtual interfaces.
    var label: String? = nil

    /// Tunnel-style interfaces that a VPN app creates. macOS keeps a few utun interfaces for its
    /// own services, so a tunnel only counts when it has an IPv4 address or a non link-local IPv6.
    var looksLikeVPN: Bool {
        guard Self.isTunnelName(name) else { return false }
        return addresses.contains { !$0.hasPrefix("fe80") }
    }

    /// A VPN tunnel that is connected right now.
    var isActiveVPN: Bool { isUp && looksLikeVPN }

    /// Wi-Fi or Ethernet that is connected right now (has more than a link-local address).
    var isActiveConnection: Bool {
        isUp && name.hasPrefix("en") && addresses.contains { !$0.hasPrefix("fe80") && !$0.hasPrefix("169.254.") }
    }

    /// Whether the name is one VPN apps use for their tunnels. Works for interfaces that are gone, too.
    static func isTunnelName(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "wg", "tun", "tap"].contains(where: name.hasPrefix)
    }

    var displayName: String {
        if name.hasPrefix("wg") { return "WireGuard (\(name))" }
        if looksLikeVPN { return "VPN tunnel (\(name))" }
        if let label { return "\(label) (\(name))" }
        return name
    }
}

enum NetworkInterfaces {
    /// All interfaces with at least one IP address.
    static func current() -> [NetworkInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var addresses: [String: [String]] = [:]
        var upState: [String: Bool] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            let flags = Int32(ifa.pointee.ifa_flags)
            let up = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            upState[name] = (upState[name] ?? false) || up
            guard let sa = ifa.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            if getnameinfo(sa, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses[name, default: []].append(String(cString: host))
            }
        }
        let labels = localizedNames()
        return addresses.keys.sorted().compactMap { name in
            guard name != "lo0" else { return nil }
            return NetworkInterface(name: name, addresses: addresses[name] ?? [], isUp: upState[name] ?? false,
                                    label: labels[name])
        }
    }

    /// The VPN tunnel that is connected right now, if any.
    static func activeVPN(in interfaces: [NetworkInterface] = current()) -> NetworkInterface? {
        interfaces.first(where: \.isActiveVPN)
    }

    /// BSD name → the name System Settings shows, e.g. "en0" → "Wi-Fi".
    private static func localizedNames() -> [String: String] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var names: [String: String] = [:]
        for iface in all {
            if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
               let label = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                names[bsd] = label
            }
        }
        return names
    }
}
