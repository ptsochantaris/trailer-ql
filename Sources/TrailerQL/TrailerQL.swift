import Foundation
import Lista

typealias JSON = [String: Sendable]

public enum TQL {
    public static let emptyList = Lista<Fragment>()

    public nonisolated(unsafe) static var debugLog: ((String) -> Void)?

    static func log(_ message: @autoclosure () -> String) {
        if let debugLog {
            debugLog(message())
        }
    }

    public enum Error: Swift.Error {
        case alreadyParsed
        case apiError(String)

        public var localizedDescription: String {
            switch self {
            case .alreadyParsed:
                "Node already parsed in previous sync"
            case let .apiError(text):
                "API error: \(text)"
            }
        }
    }
}
