import Foundation
import Lista
import TrailerJson

public struct Query: Sendable {
    @globalActor
    public enum NodeActor {
        public actor ActorType {}
        public static let shared = ActorType()
    }

    public typealias PerNodeBlock = @NodeActor (ParseOutput) async throws(TQL.Error) -> Void

    public let name: String

    let rootElement: Scanning
    private let parent: Node?
    private let allowsEmptyResponse: Bool
    private let checkRate: Bool

    let perNodeBlock: PerNodeBlock?

    public init(name: String, rootElement: Scanning, parent: Node? = nil, allowsEmptyResponse: Bool = false, checkRate: Bool = true, perNode: PerNodeBlock? = nil) {
        self.rootElement = rootElement
        self.parent = parent
        self.name = name
        self.allowsEmptyResponse = allowsEmptyResponse
        self.checkRate = checkRate
        perNodeBlock = perNode
    }

    init(from query: Query, with newRootElement: Scanning) {
        rootElement = newRootElement
        parent = query.parent
        name = query.name
        allowsEmptyResponse = query.allowsEmptyResponse
        perNodeBlock = query.perNodeBlock
        checkRate = query.checkRate
    }

    public static func batching(_ name: String, groupName: String, idList: some Sequence<String>, checkRate: Bool = true, maxCost: Int = 500_000, perNode: PerNodeBlock? = nil, @ElementsBuilder fields: () -> [Element]) -> Lista<Query> {
        let template = Group("items", fields: fields)
        let batchLimit = template.recommendedLimit(upTo: maxCost)
        let queries = Lista<Query>()

        func createQuery(from chunk: [String]) {
            let batchGroup = BatchGroup(name: groupName, templateGroup: template, idList: chunk)
            let query = Query(name: name, rootElement: batchGroup, checkRate: checkRate, perNode: perNode)
            queries.append(query)
        }

        var chunk = [String]()
        chunk.reserveCapacity(batchLimit)
        for id in idList {
            chunk.append(id)
            if chunk.count == batchLimit {
                createQuery(from: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            createQuery(from: chunk)
        }

        return queries
    }

    private var rootQueryText: String {
        if let parent {
            "node(id: \"\(parent.id)\") { ... on \(parent.elementType) { " + rootElement.queryText + " } }"
        } else {
            rootElement.queryText
        }
    }

    private var fragmentQueryText: String {
        let fragments = Set(rootElement.fragments)
        return fragments.map(\.declaration).joined(separator: " ")
    }

    public var queryText: String {
        let suffix = if checkRate {
            " rateLimit { limit cost remaining resetAt nodeCount } }"
        } else {
            " }"
        }
        return fragmentQueryText + " { " + rootQueryText + suffix
    }

    public var logPrefix: String {
        "(TQL '\(name)') "
    }

    public var nodeCost: Int {
        rootElement.nodeCost
    }

    public func processResponse(from data: Data) async throws(TQL.Error) -> Lista<Query> {
        guard
            let json = try? data.asTypedJson() else {
            let msg = "Could not parse JSON from data"
            throw TQL.Error.apiError("\(logPrefix)" + msg)
        }
        return try await processResponse(from: json)
    }

    public func processResponse(from json: TypedJson.Entry) async throws(TQL.Error) -> Lista<Query> {
        guard
            let allData = json.potentialObject(named: "data"),
            let data = (parent == nil) ? allData : allData.potentialObject(named: "node"),
            let topData = try? data[rootElement.name]
        else {
            if allowsEmptyResponse {
                return Lista()
            }
            let msg = "Could not read a `data` or `data.node` from payload"
            throw TQL.Error.apiError("\(logPrefix)" + msg)
        }

        await TQL.log("\(logPrefix)Scanning result")

        let extraQueries = Lista<Query>()
        try await rootElement.scan(query: self, pageData: topData, parent: parent, relationship: rootElement.name, extraQueries: extraQueries)

        try? await perNodeBlock?(.queryPageComplete)

        if extraQueries.count == 0 {
            await TQL.log("\(logPrefix)Parsed all pages")
            try? await perNodeBlock?(.queryComplete)

        } else {
            await TQL.log("\(logPrefix)Needs more page data (\(extraQueries.count) queries)")
        }
        return extraQueries
    }
}
