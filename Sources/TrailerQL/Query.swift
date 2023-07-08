import Foundation

public struct Query {
    @globalActor
    public enum NodeActor {
        public actor ActorType {}
        public static let shared = ActorType()
    }
    
    public typealias PerNodeBlock = @NodeActor (Node) async throws -> Void

    public let name: String
    
    let rootElement: Scanning
    private let parent: Node?
    private let allowsEmptyResponse: Bool
    
    let perNodeBlock: PerNodeBlock?
    
    public init(name: String, rootElement: Scanning, parent: Node? = nil, allowsEmptyResponse: Bool = false, perNode: PerNodeBlock? = nil) {
        self.rootElement = rootElement
        self.parent = parent
        self.name = name
        self.allowsEmptyResponse = allowsEmptyResponse
        perNodeBlock = perNode
    }
    
    init(from query: Query, with newRootElement: Scanning) {
        rootElement = newRootElement
        parent = query.parent
        name = query.name
        allowsEmptyResponse = query.allowsEmptyResponse
        perNodeBlock = query.perNodeBlock
    }
    
    public static func batching(_ name: String, idList: [String], perNode: PerNodeBlock? = nil, @ElementsBuilder fields: () -> [Element]) -> List<Query> {
        var list = ArraySlice(idList)
        let template = Group("items", fields: fields)
        let batchLimit = template.recommendedLimit
        let queries = List<Query>()
        
        while !list.isEmpty {
            let chunk = Array(list.prefix(batchLimit))
            let batchGroup = BatchGroup(templateGroup: template, idList: chunk)
            let query = Query(name: name, rootElement: batchGroup, perNode: perNode)
            queries.append(query)
            list = list.dropFirst(batchLimit)
        }
        return queries
    }
    
    private var rootQueryText: String {
        if let parent {
            return "node(id: \"\(parent.id)\") { ... on \(parent.elementType) { " + rootElement.queryText + " } }"
        } else {
            return rootElement.queryText
        }
    }
    
    private var fragmentQueryText: String {
        let fragments = Set(rootElement.fragments)
        return fragments.map(\.declaration).joined(separator: " ")
    }
    
    public var queryText: String {
        fragmentQueryText + " { " + rootQueryText + " rateLimit { limit cost remaining resetAt nodeCount } }"
    }
    
    public var logPrefix: String {
        "(TQL '\(name)') "
    }
    
    public var nodeCost: Int {
        rootElement.nodeCost
    }
    
    public func processResponse(from json: Any?) async throws -> List<Query> {
        guard
            let json = json as? [String: Any],
            let allData = json["data"] as? JSON,
            let data = (parent == nil) ? allData : allData["node"] as? [String: Any],
            let topData = data[rootElement.name]
        else {
            if allowsEmptyResponse {
                return List()
            }
            let msg = "Could not read a `data` or `data.node` from payload"
            throw TQL.Error.apiError("\(logPrefix)" + msg)
        }
        
        TQL.log("\(logPrefix)Scanning result")
        
        let extraQueries = List<Query>()
        try await rootElement.scan(query: self, pageData: topData, parent: parent, extraQueries: extraQueries)
        if extraQueries.count == 0 {
            TQL.log("\(logPrefix)Parsed all pages")
        } else {
            TQL.log("\(logPrefix)Needs more page data (\(extraQueries.count) queries)")
        }
        return extraQueries
    }
}

