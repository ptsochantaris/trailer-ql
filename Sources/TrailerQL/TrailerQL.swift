import Foundation
import Lista
import Synchronization

@globalActor
public enum LogActor {
    public final actor ActorType {}
    public static let shared = ActorType()
}

public enum TQL {
    public static let emptyList = Lista<Fragment>()

    @LogActor
    public static var debugLog: ((String) -> Void)? {
        didSet {
            sinkInstalled.store(debugLog != nil, ordering: .relaxed)
        }
    }

    /// Tracks whether ``debugLog`` is set, readable without entering ``LogActor``.
    private static let sinkInstalled = Atomic<Bool>(false)

    /// Scanning calls this for every group it walks, so when nothing is listening it has to cost
    /// nothing. Reading ``debugLog`` means entering ``LogActor``, and the suspension that needs
    /// would be paid whether or not there was anything to log, hence the flag.
    static func log(_ message: @autoclosure @Sendable () -> String) async {
        guard sinkInstalled.load(ordering: .relaxed) else {
            return
        }
        await deliver(message())
    }

    @LogActor
    private static func deliver(_ message: String) {
        debugLog?(message)
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
