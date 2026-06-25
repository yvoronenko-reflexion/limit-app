import Foundation
import CryptoKit

/// Parent PIN gate. Stores only a salted SHA-256 hash, never the PIN itself.
///
/// Note: SHA-256 is adequate for a short PIN guarding a child-facing UI; it is not
/// meant to withstand an offline attacker with the state file. If that ever matters,
/// switch `hash` to PBKDF2/scrypt.
public enum ParentPIN {
    public struct Stored: Codable, Equatable {
        public var saltBase64: String
        public var hashBase64: String

        public init(saltBase64: String, hashBase64: String) {
            self.saltBase64 = saltBase64
            self.hashBase64 = hashBase64
        }
    }

    /// Create a stored hash for `pin`. `saltProvider` is injectable for tests; when nil a
    /// cryptographically random salt is used.
    public static func make(pin: String, saltProvider: (() -> Data)? = nil) -> Stored {
        let salt = saltProvider?() ?? randomSalt()
        let digest = hash(pin: pin, salt: salt)
        return Stored(saltBase64: salt.base64EncodedString(),
                      hashBase64: digest.base64EncodedString())
    }

    /// Constant-time verification of `pin` against a stored hash.
    public static func verify(pin: String, against stored: Stored) -> Bool {
        guard let salt = Data(base64Encoded: stored.saltBase64),
              let expected = Data(base64Encoded: stored.hashBase64) else { return false }
        let actual = hash(pin: pin, salt: salt)
        return constantTimeEquals(actual, expected)
    }

    private static func hash(pin: String, salt: Data) -> Data {
        var data = salt
        data.append(Data(pin.utf8))
        return Data(SHA256.hash(data: data))
    }

    private static func randomSalt(count: Int = 16) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
