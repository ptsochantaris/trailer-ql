import Foundation
import TrailerJson

public enum ParseOutput: Sendable {
    case node(Node), queryPageComplete, queryComplete
}

public final class Node: Hashable, Sendable {
    public let id: String
    public let elementType: String
    public let jsonPayload: TypedJson.Entry
    public let parent: Node?
    public let relationship: String?
    public nonisolated(unsafe) var flags: Int

    init?(jsonPayload: TypedJson.Entry, parent: Node?, relationship: String?, flags: Int = 0) {
        guard let id = jsonPayload.potentialString(named: "id"),
              let elementType = jsonPayload.potentialString(named: "__typename")
        else { return nil }

        self.id = id
        self.elementType = elementType
        self.jsonPayload = jsonPayload
        self.parent = parent
        self.relationship = relationship
        self.flags = flags
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        if let parentId = parent?.id {
            hasher.combine(parentId)
        }
    }

    public static func == (lhs: Node, rhs: Node) -> Bool {
        (lhs.id == rhs.id) && (lhs.parent?.id == rhs.parent?.id)
    }
}
