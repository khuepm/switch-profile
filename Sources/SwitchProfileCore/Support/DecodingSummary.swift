import Foundation

extension DecodingError {
    /// Short description for error messages: coding path plus the debug description.
    var summary: String {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch self {
        case .dataCorrupted(let context):
            return "data corrupted at '\(path(context.codingPath))': \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "missing key '\(path(context.codingPath + [key]))'"
        case .typeMismatch(_, let context):
            return "type mismatch at '\(path(context.codingPath))': \(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "null value at '\(path(context.codingPath))': \(context.debugDescription)"
        @unknown default:
            return String(describing: self)
        }
    }
}
