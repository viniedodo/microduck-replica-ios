import Foundation

/// 把用户输入解析成可打开的 Studio 地址。
/// 只接受 http/https；默认端口 8000；路径由「手机 / 桌面」开关决定。
enum ConsolePage: String, Equatable, Codable, CaseIterable {
    case mobile
    case desktop

    var path: String { self == .mobile ? "/m" : "/" }

    var title: String { self == .mobile ? "手机控制台（/m）" : "桌面控制台（/）" }
}

struct RobotEndpoint: Equatable {
    var scheme: String
    var host: String
    var port: Int
    var page: ConsolePage

    var url: URL {
        var c = URLComponents()
        c.scheme = scheme
        if host.contains(":") && !host.hasPrefix("[") {
            c.host = host
            // URLComponents 对裸 IPv6 需要通过 percent-safe host assignment.
        } else {
            c.host = host
        }
        c.port = port
        c.path = page.path
        if let url = c.url {
            return url
        }
        // 回退：手工拼接（IPv6 加括号）
        let hostPart = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return URL(string: "\(scheme)://\(hostPart):\(port)\(page.path)")!
    }

    /// 用于同源判断和界面展示，不含路径。
    var origin: String {
        let hostPart = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(hostPart):\(port)"
    }

    var displayURL: String { url.absoluteString }
}

enum RobotAddressError: Error, Equatable, LocalizedError {
    case empty
    case invalidScheme
    case credentialsForbidden
    case missingHost
    case invalidHost
    case invalidPort
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入机器人地址。"
        case .invalidScheme:
            return "只支持 http 或 https 地址。"
        case .credentialsForbidden:
            return "请不要在地址里写入账号或密码。"
        case .missingHost:
            return "地址里没有主机名。"
        case .invalidHost:
            return "主机名或 IP 格式不正确。"
        case .invalidPort:
            return "端口必须是 1 到 65535 之间的数字。"
        case .invalidURL:
            return "无法解析这个地址。"
        }
    }
}

enum RobotAddress {
    static let defaultPort = 8000
    static let defaultScheme = "https"
    private static let rawKey = "robotAddress.raw"
    private static let pageKey = "robotAddress.page"

    /// 示例只用于占位说明，不是某台真实设备。
    static let examples: [String] = [
        "https://duck-xxxx.local:8000/m",
        "http://duck-xxxx.local:8000/m",
        "https://10.42.0.1:8000/m",
        "http://192.168.1.23:8000/m",
    ]

    static func parse(_ raw: String, page: ConsolePage) throws -> RobotEndpoint {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw RobotAddressError.empty }

        if trimmed.contains("@") {
            // 拒绝 user:pass@host，避免把凭证写进历史或日志习惯里
            throw RobotAddressError.credentialsForbidden
        }

        try rejectDisallowedScheme(trimmed)

        var text = trimmed
        if schemePrefix(trimmed.lowercased()) == nil {
            text = "\(defaultScheme)://" + text
        }

        guard let components = URLComponents(string: text) else {
            throw RobotAddressError.invalidURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw RobotAddressError.invalidScheme
        }
        if components.user != nil || components.password != nil {
            throw RobotAddressError.credentialsForbidden
        }

        var host = (components.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("[") && host.hasSuffix("]") && host.count >= 2 {
            host = String(host.dropFirst().dropLast())
        }
        if host.isEmpty { throw RobotAddressError.missingHost }
        if looksLikeIPv4(host) {
            if !isIPv4(host) { throw RobotAddressError.invalidHost }
        } else if isIPv6(host) {
            // keep IPv6 literal as parsed
        } else if isHostname(host) {
            host = host.lowercased()
        } else {
            throw RobotAddressError.invalidHost
        }

        let port: Int
        if let p = components.port {
            guard (1...65535).contains(p) else { throw RobotAddressError.invalidPort }
            port = p
        } else {
            port = defaultPort
        }

        return RobotEndpoint(scheme: scheme, host: host, port: port, page: page)
    }

    static func loadSaved() -> (raw: String, page: ConsolePage)? {
        let raw = UserDefaults.standard.string(forKey: rawKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return nil }
        let page = ConsolePage(rawValue: UserDefaults.standard.string(forKey: pageKey) ?? "") ?? .mobile
        return (raw, page)
    }

    static func save(raw: String, page: ConsolePage) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: rawKey)
        UserDefaults.standard.set(page.rawValue, forKey: pageKey)
    }

    static func matchesOrigin(endpoint: RobotEndpoint, scheme: String, host: String, port: Int) -> Bool {
        let s = scheme.lowercased()
        var h = host
        if h.hasPrefix("[") && h.hasSuffix("]") && h.count >= 2 {
            h = String(h.dropFirst().dropLast())
        }
        var p = port
        if p == 0 {
            p = (s == "https") ? 443 : 80
        }
        return s == endpoint.scheme
            && h.caseInsensitiveCompare(endpoint.host) == .orderedSame
            && p == endpoint.port
    }

    private static func schemePrefix(_ lowered: String) -> String? {
        if let r = lowered.range(of: "://") {
            return String(lowered[..<r.lowerBound])
        }
        return nil
    }

    static func isValidHost(_ host: String) -> Bool {
        if looksLikeIPv4(host) { return isIPv4(host) }
        if isIPv6(host) { return true }
        return isHostname(host)
    }

    /// javascript:alert(1) 这类「有冒号但不是 http(s):// 或 host:端口」的输入一律拒绝。
    private static func rejectDisallowedScheme(_ trimmed: String) throws {
        guard let colon = trimmed.firstIndex(of: ":") else { return }
        let head = String(trimmed[..<colon])
        let rest = String(trimmed[trimmed.index(after: colon)...])
        let schemeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+.-"))
        guard let first = head.unicodeScalars.first, CharacterSet.letters.contains(first) else { return }
        if head.unicodeScalars.contains(where: { !schemeChars.contains($0) }) { return }
        let lowered = head.lowercased()
        if lowered == "http" || lowered == "https" {
            if !rest.hasPrefix("//") { throw RobotAddressError.invalidScheme }
            return
        }
        if rest.hasPrefix("//") { throw RobotAddressError.invalidScheme }
        let portPart = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rest
        if portPart.isEmpty { return }
        if let n = Int(portPart), (1...65535).contains(n) { return }
        throw RobotAddressError.invalidScheme
    }

    static func looksLikeIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for p in parts {
            if p.isEmpty || p.count > 3 { return false }
            if p.count > 1 && p.hasPrefix("0") { return false }
            guard let n = Int(p, radix: 10), (0...255).contains(n) else { return false }
            // 拒绝非数字（Int 已处理）
            if p.contains(where: { !$0.isNumber }) { return false }
        }
        return true
    }

    static func isIPv6(_ host: String) -> Bool {
        var addr = host
        if addr.hasPrefix("[") && addr.hasSuffix("]") {
            addr = String(addr.dropFirst().dropLast())
        }
        var storage = in6_addr()
        return addr.withCString { inet_pton(AF_INET6, $0, &storage) == 1 }
    }

    static func isHostname(_ host: String) -> Bool {
        // 允许 duck-xxxx.local、localhost、普通域名；每段以字母或数字开头结尾，中间可有连字符。
        if host.hasPrefix(".") || host.hasSuffix(".") || host.contains("..") { return false }
        if host.count > 253 { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        let re = try! NSRegularExpression(pattern: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", options: [.caseInsensitive])
        for label in labels {
            if label.isEmpty || label.count > 63 { return false }
            let s = String(label)
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            if re.firstMatch(in: s, options: [], range: range) == nil { return false }
        }
        return true
    }
}
