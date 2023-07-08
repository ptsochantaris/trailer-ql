import Foundation

public struct BatchGroup: Scanning {
    public let id: UUID
    public let name: String
    
    private let idList: [String]
    private let templateGroup: Group
    
    public init(templateGroup: Group, idList: [String]) {
        id = UUID()
        name = "nodes"
        self.templateGroup = templateGroup
        self.idList = idList
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
        "nodes(ids: [\"" + idList.joined(separator: "\",\"") + "\"]) { " + templateGroup.fields.map(\.queryText).joined(separator: " ") + " }"
    }
    
    public var fragments: List<Fragment> {
        templateGroup.fragments
    }
    
    public func scan(query: Query, pageData: Any, parent: Node?, extraQueries: List<Query>) async throws {
        guard let nodes = pageData as? any Sequence else { return }
        
        for pageData in nodes.compactMap({ $0 as? JSON }) {
            try await templateGroup.scan(query: query, pageData: pageData, parent: parent, extraQueries: extraQueries)
        }
    }
}

