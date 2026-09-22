import Foundation
import CryptoKit

enum RequestAuthenticator {
    // 32-byte XOR-obfuscated secret key as extracted from Mach-O binary
    private static let encryptedKeyBytes: [UInt8] = [
        30, 31, 3, 19, 6, 7, 22, 32, 54, 62, 48, 49, 32, 47, 55, 46,
        10, 11, 0, 5, 10, 99, 122, 115, 103, 116, 72, 123, 115, 100, 118, 48
    ]
    
    private static let xorMask: [UInt8] = [
        95, 75, 71, 84, 75, 65, 67, 69, 95, 93, 69, 67, 90, 68, 82, 69,
        63, 57, 51, 49, 55, 86, 79, 68, 82, 79, 126, 79, 70, 83, 67, 5
    ]
    
    // Result: "ATDGMFUeicurzkek5234=5575;645755"
    static var secretKey: String {
        let decryptedBytes = zip(encryptedKeyBytes, xorMask).map { $0 ^ $1 }
        return String(bytes: decryptedBytes, encoding: .utf8) ?? ""
    }
    
    static func hash(for url: URL) -> String {
        let input = url.absoluteString + secretKey
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    static func addingHash(to request: URLRequest) -> URLRequest {
        var modified = request
        if let url = request.url {
            let signature = hash(for: url)
            modified.setValue(signature, forHTTPHeaderField: "X-UTHSEB-Request-Hash")
        }
        return modified
    }
    
    static func requestHasValidHash(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              let providedHash = request.value(forHTTPHeaderField: "X-UTHSEB-Request-Hash") else {
            return false
        }
        let expectedHash = hash(for: url)
        return providedHash == expectedHash
    }
}
