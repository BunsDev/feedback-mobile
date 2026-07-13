import Foundation

public enum APIError: Error, Equatable, Sendable {
    case unauthorized
    case notFound
    case rateLimited
    case server(status: Int, code: String?)
    case transport(String)
    case decoding(String)
    case auth(code: String?, message: String?)
}
