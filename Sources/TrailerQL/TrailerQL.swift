import Foundation
import Lista

@globalActor
public enum LogActor {
    public final actor ActorType {}
    public static let shared = ActorType()
}

public enum TQL {
    public static let emptyList = Lista<Fragment>()

    @LogActor
    public static var debugLog: ((String) -> Void)?

    @LogActor
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
