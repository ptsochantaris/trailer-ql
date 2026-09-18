import Foundation
import Lista
import TrailerJson

public struct BatchGroup: Scanning {
    public let id: UUID
    public let name: String

    private let idList: [String]
    private let templateGroup: Group

    /// Built once here rather than per access: a batch of queries shares one template, so
    /// regenerating this text for each of them repeated the same subtree walk.
    public let queryText: String

    public init(name: String, templateGroup: Group, idList: some Collection<String>) {
        id = UUID()
        self.name = name
        self.templateGroup = templateGroup
        let idList = Array(idList)
        self.idList = idList
        queryText = BatchGroup.makeQueryText(name: name, idList: idList, templateGroup: templateGroup)
        assert(idList.count <= 100)
    }

    private init(cloning: BatchGroup, templateGroup: Group, rootId: String) {
        id = cloning.id
        let name = cloning.name
        self.name = name
        let idList = [rootId]
        self.idList = idList
        self.templateGroup = templateGroup
        queryText = BatchGroup.makeQueryText(name: name, idList: idList, templateGroup: templateGroup)
        assert(idList.count <= 100)
    }

    private static func makeQueryText(name: String, idList: [String], templateGroup: Group) -> String {
        // The field text is appended, rather than interpolated into the suffix, so that it is
        // copied once on the way in rather than twice.
        let fields = templateGroup.fieldsQueryText
        var text = idList.assembled(separator: "\",\"", prefix: "\(name)(ids: [\"", suffix: "\"]) { ")
        text.reserveCapacity(text.utf8.count + fields.utf8.count + 2)
        text += fields
        text += " }"
        return text
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
