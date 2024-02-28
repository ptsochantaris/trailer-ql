import Foundation

public enum ParseOutput {
    case node(Node), queryPageComplete, queryComplete
}

public final class Node: Hashable {
    public let id: String
    public let elementType: String
    public let jsonPayload: [String: Any]
    public let parent: Node?
    public let relationship: String?
    public var flags: Int

    init?(jsonPayload: JSON, parent: Node?, relationship: String?) {
        guard let id = jsonPayload["id"] as? String,
              let elementType = jsonPayload["__typename"] as? String
        else { return nil }

        self.id = id
        self.elementType = elementType
        self.jsonPayload = jsonPayload
        self.parent = parent
        self.relationship = relationship
        flags = 0
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
