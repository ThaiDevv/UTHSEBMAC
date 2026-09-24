import Foundation

enum AiMoodlePolicy {
    private static let allowedAiDomains: [String] = [
        "13.211.200.63",
        "localhost",
        "127.0.0.1"
    ]
    
    private static let allowedAiDomainSuffixes: [String] = [
        "tools-store.com",
        "tools-store.vn"
    ]
    
    private static let allowedGeminiDomains: [String] = [
        "googleapis.com"
    ]
    
    static func isAllowedAiApiURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        
        guard let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() else {
            return false
        }
        
        if host == "localhost" || host == "127.0.0.1" || DomainPolicy.isLoopbackHost(host) {
            return true
        }
        
        for domain in allowedAiDomains {
            if host == domain || host.hasSuffix("." + domain) {
                return true
            }
        }
        
        for suffix in allowedAiDomainSuffixes {
            if host == suffix || host.hasSuffix("." + suffix) {
                return true
            }
        }
        
        return false
    }
    
    static func isAllowedGeminiURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        
        guard let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() else {
            return false
        }
        
        if host == "generativelanguage.googleapis.com" ||
            host == "gemini.googleapis.com" ||
            host.hasSuffix(".generativelanguage.googleapis.com") ||
            host.hasSuffix(".googleapis.com") {
            return true
        }
        
        return false
    }
    
    static func isAllowedAiURL(_ url: URL) -> Bool {
        return isAllowedAiApiURL(url) || isAllowedGeminiURL(url)
    }
    
    static func isAllowedAiURL(string: String) -> Bool {
        guard let url = URL(string: string) else {
            return false
        }
        return isAllowedAiURL(url)
    }
}
