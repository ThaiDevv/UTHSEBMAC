import Foundation

enum DomainPolicy {
    private static let allowedDomainSuffixes: [String] = [
        "ut.edu.vn",
        "uth.edu.vn"
    ]
    
    struct BlockedNavigationReason {
        let title: String
        let message: String
    }
    
    static func isLoopbackHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "::1" || trimmed == "0:0:0:0:0:0:0:1" {
            return true
        }
        let parts = trimmed.split(separator: ".")
        if parts.count == 4 {
            for part in parts {
                guard let num = Int(part), num >= 0 && num <= 255 else {
                    return false
                }
            }
            if parts[0] == "127" {
                return true
            }
        }
        return false
    }
    
    static func isAllowedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        
        guard let host = url.host?.lowercased() else {
            return false
        }
        
        if host == "localhost" || isLoopbackHost(host) {
            return true
        }
        
        for suffix in allowedDomainSuffixes {
            if host == suffix || host.hasSuffix("." + suffix) {
                return true
            }
        }
        
        return false
    }
    
    static func requestedTarget(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "uthseb" else {
            return nil
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        if let queryItems = components.queryItems {
            for item in queryItems where item.name.lowercased() == "url" {
                if let value = item.value, let targetURL = URL(string: value) {
                    return targetURL
                }
            }
        }
        
        return nil
    }
    
    static func launchTarget(from url: URL) -> URL? {
        if isAllowedWebURL(url) {
            return url
        }
        if let requested = requestedTarget(from: url), isAllowedWebURL(requested) {
            return requested
        }
        return nil
    }
    
    static func blockedTargetLabel(_ url: URL) -> String {
        return url.absoluteString
    }
    
    static func blockedNavigationReason(for url: URL) -> BlockedNavigationReason {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            let schemeName = url.scheme ?? "không xác định"
            return BlockedNavigationReason(
                title: "Giao thức không được phép",
                message: "\"\(schemeName)\" không được phép cho \"\(url.absoluteString)\".\n\nUTH SEB chỉ mở trang HTTP/HTTPS trong danh sách được phép và sẽ đóng ứng dụng."
            )
        }
        
        return BlockedNavigationReason(
            title: "Tên miền không được phép",
            message: "\"\(url.absoluteString)\" không được phép.\n\nUTH SEB sẽ đóng ứng dụng."
        )
    }
}
