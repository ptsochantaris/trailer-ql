import Foundation

typealias JSON = [String: Any]

@globalActor
public enum NodeActor {
    public actor ActorType {}
    public static let shared = ActorType()
}

public typealias PerNodeBlock = @NodeActor (Node) async throws -> Void

public let idField = Field("id")

public let emptyList = LinkedList<Fragment>()

public enum TQLError: Error {
    case alreadyParsed
    case apiError(String)

    public var localizedDescription: String {
        switch self {
        case .alreadyParsed:
            return "Node already parsed in previous sync"
        case let .apiError(text):
            return "API error: \(text)"
        }
    }
}

func log(_ message: @autoclosure () -> String) {
    // TODO
    print(message())
}
