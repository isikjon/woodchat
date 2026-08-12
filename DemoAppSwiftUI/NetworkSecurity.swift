//
// WoodChat — внутренний мессенджер Woodstream.
// Пиннинг сертификатов: защищает логин и REST API от MITM (подменённый CA,
// корпоративный прокси, вредоносный профиль). Проверяем SPKI-отпечаток
// хотя бы одного сертификата в цепочке.
//

import CryptoKit
import Foundation

enum WoodChatPinning {
    /// SPKI-отпечатки (SHA-256, base64) сертификатов chat.woodstream.online.
    /// Закреплены лист, промежуточный и корневой — при плановом продлении листа
    /// соединение не рвётся (совпадает промежуточный/корневой), но подмена
    /// сторонним CA отсекается.
    static let pinnedSPKI: Set<String> = [
        // Лист CN=chat.woodstream.online (RSA 2048)
        "xUmv/FkJzrYVg88xMgpEcnW7FgfL7C/F26wx4GU/aic=",
        // Промежуточный CN=YR1 (RSA 2048)
        "LoMHBotttiDko50Gi13uXW71eIy7LAttI+rYT8wXF4w=",
        // Корневой CN=Root YR (RSA 4096)
        "fk6IOKit1ild5647BH06ujSIq5XbCgqlbYl6ANhhi88="
    ]

    static let pinnedHost = "chat.woodstream.online"

    // ASN.1-заголовки SubjectPublicKeyInfo: SecKeyCopyExternalRepresentation
    // отдаёт «сырой» ключ без них, дописываем сами перед хешированием.
    private static let rsa2048Header: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]
    private static let rsa4096Header: [UInt8] = [
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
    ]
    private static let ecP256Header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
        0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00
    ]
    private static let ecP384Header: [UInt8] = [
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
        0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
    ]

    /// SPKI-отпечаток публичного ключа сертификата (или nil, если тип ключа неизвестен).
    static func spkiHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = publicKey(for: certificate),
              let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let attributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any] else {
            return nil
        }

        let keyType = attributes[kSecAttrKeyType] as? String
        let keySize = (attributes[kSecAttrKeySizeInBits] as? Int) ?? 0

        let header: [UInt8]
        if keyType == (kSecAttrKeyTypeRSA as String) {
            switch keySize {
            case 2048: header = rsa2048Header
            case 4096: header = rsa4096Header
            default: return nil
            }
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            switch keySize {
            case 256: header = ecP256Header
            case 384: header = ecP384Header
            default: return nil
            }
        } else {
            return nil
        }

        var spki = Data(header)
        spki.append(keyData)
        let digest = SHA256.hash(data: spki)
        return Data(digest).base64EncodedString()
    }

    private static func publicKey(for certificate: SecCertificate) -> SecKey? {
        if #available(iOS 12.0, *) {
            return SecCertificateCopyKey(certificate)
        }
        return nil
    }

    /// true, если в цепочке доверия есть закреплённый ключ.
    static func validate(serverTrust: SecTrust) -> Bool {
        let count = SecTrustGetCertificateCount(serverTrust)
        guard count > 0 else { return false }

        for index in 0 ..< count {
            let certificate: SecCertificate?
            if #available(iOS 15.0, *) {
                certificate = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate])?[safe: index]
            } else {
                certificate = SecTrustGetCertificateAtIndex(serverTrust, index)
            }
            guard let certificate,
                  let hash = spkiHash(for: certificate) else { continue }
            if pinnedSPKI.contains(hash) {
                return true
            }
        }
        return false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Делегат URLSession с пиннингом для запросов к chat.woodstream.online.
final class WoodChatPinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Пиннинг только для нашего хоста; всё прочее — обычная проверка системы.
        guard challenge.protectionSpace.host == WoodChatPinning.pinnedHost else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Сначала системная проверка валидности цепочки, затем сверка отпечатка.
        var error: CFError?
        let systemTrusted = SecTrustEvaluateWithError(serverTrust, &error)
        if systemTrusted, WoodChatPinning.validate(serverTrust: serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

/// Общая сессия с пиннингом. Используется для логина, REST API и загрузки аватара.
enum WoodChatNetwork {
    static let pinnedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(
            configuration: configuration,
            delegate: WoodChatPinningDelegate(),
            delegateQueue: nil
        )
    }()
}
