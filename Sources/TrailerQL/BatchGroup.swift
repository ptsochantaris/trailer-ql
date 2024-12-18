import Foundation
import Lista
import TrailerJson

public struct BatchGroup: Scanning {
    public let id: UUID
    public let name: String

    private let idList: [String]
    private let templateGroup: Group

    public init(name: String, templateGroup: Group, idList: some Collection<String>) {
        id = UUID()
        self.name = name
        self.templateGroup = templateGroup
        self.idList = Array(idList)
        assert(idList.count <= 100)
    }

    private init(cloning: BatchGroup, templateGroup: Group, rootId: String) {
        id = cloning.id
        name = cloning.name
        idList = [rootId]
        self.templateGroup = templateGroup
        assert(idList.count <= 100)
    }

    public func asShell(for element: Element, batchRootId: String?) -> Element? {
        if id == element.id {
            return element
        }

        if let batchRootId, let shellGroup = templateGroup.asShell(for: element, batchRootId: nil) as? Group {
            return BatchGroup(cloning: self, templateGroup: shellGroup, rootId: batchRootId)
        }

        return nil
    }

    public var nodeCost: Int {
        let count = idList.count
        return count + count * templateGroup.nodeCost
    }

    public var queryText: String {
        "\(name)(ids: [\"" + idList.joined(separator: "\",\"") + "\"]) { " + templateGroup.fields.map(\.queryText).joined(separator: " ") + " }"
    }

    public var fragments: Lista<Fragment> {
        templateGroup.fragments
    }

    public func scan(query: Query, pageData: TypedJson.Entry, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws(TQL.Error) {
        guard let nodes = pageData.potentialArray else { return }

        for data in nodes {
            try await templateGroup.scan(query: query, pageData: data, parent: parent, relationship: relationship, extraQueries: extraQueries)
        }
    }
}
