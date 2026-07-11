import CryptoKit
import Foundation

public enum ZoteroObjectKey {
    // MARK: Public

    public static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0 ..< 8).map { _ in alphabet.randomElement(using: &generator) ?? "2" })
    }

    public static func deterministic(namespace: String, value: String) -> String {
        let digest = SHA256.hash(data: Data("\(namespace):\(value)".utf8))
        return digest.prefix(8).map { alphabet[Int($0) % alphabet.count] }.reduce(into: "") { result, character in
            result.append(character)
        }
    }

    public static func isValid(_ value: String) -> Bool {
        value.count == 8 && value.allSatisfy(alphabet.contains)
    }

    // MARK: Private

    private static let alphabet: Array = .init("23456789ABCDEFGHIJKLMNPQRSTUVWXYZ")
}
