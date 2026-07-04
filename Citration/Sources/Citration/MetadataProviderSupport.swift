import Foundation

func requireEndpointURL(_ rawURL: String, providerName: String) -> URL {
    guard let url = URL(string: rawURL) else {
        fatalError("Invalid default endpoint URL for \(providerName): \(rawURL)")
    }
    return url
}
