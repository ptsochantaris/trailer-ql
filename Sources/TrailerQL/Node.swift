import Foundation

public enum ParseOutput: Sendable {
    case node(Node), queryPageComplete, queryComplete
}

public final class Node: Hashable, Sendable {
    public let id: String
    public let elementType: String
    public let jsonPayload: [String: Sendable]
    public let parent: Node?
    public let relationship: String?
    public let flags: Int

    init?(jsonPayload: JSON, parent: Node?, relationship: String?, flags: Int = 0) {
        guard let id = jsonPayload["id"] as? String,
              let elementType = jsonPayload["__typename"] as? String
        else { return nil }

        self.id = id
        self.elementType = elementType
        self.jsonPayload = jsonPayload
        self.parent = parent
        self.relationship = relationship
        self.flags = flags
    }

    private init(id: String, elementType: String, jsonPayload: [String: Sendable], parent: Node?, relationship: String?, flags: Int = 0) {
        self.id = id
        self.elementType = elementType
        self.jsonPayload = jsonPayload
        self.parent = parent
        self.relationship = relationship
        self.flags = flags
    }

    func withFlags(_ newFlags: Int) -> Node {
        .init(id: id, elementType: elementType, jsonPayload: jsonPayload, parent: parent, relationship: relationship, flags: newFlags)
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
