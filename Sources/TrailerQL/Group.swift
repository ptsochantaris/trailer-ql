import Foundation
import Lista
import TrailerJson

public struct Group: Scanning {
    public enum Paging: Sendable {
        case none, first(count: Int, paging: Bool), last(count: Int), max
    }

    public typealias Param = (name: String, value: LosslessStringConvertible & Sendable)

    public let id: UUID
    public let name: String
    let fields: [Element]
    let paging: Paging
    private let extraParams: [Param]
    private let lastCursor: String?

    public init(_ name: String, _ params: Param..., paging: Paging = .none, @ElementsBuilder fields: () -> [Element]) {
        id = UUID()
        self.name = name
        self.fields = fields()
        self.paging = paging
        extraParams = params
        lastCursor = nil
    }

    private init(cloning group: Group, name: String? = nil, lastCursor: String? = nil, replacedFields: [Element]? = nil) {
        id = group.id
        self.name = name ?? group.name
        fields = replacedFields ?? group.fields
        paging = group.paging
        extraParams = group.extraParams
        self.lastCursor = lastCursor
    }

    public func asShell(for element: Element, batchRootId _: String?) -> Element? {
        if element.id == id {
            return element
        }

        let replacementFields = fields.compactMap { $0.asShell(for: element, batchRootId: nil) }
        if replacementFields.isEmpty {
            return nil
        }
        return Group(cloning: self, replacedFields: replacementFields)
    }

    public var nodeCost: Int {
        let fieldCost = fields.reduce(0) { $0 + $1.nodeCost }
        switch paging {
        case .none:
            return fieldCost

        case .max:
            return 100 + fieldCost * 100

        case let .first(count, _), let .last(count):
            return count + fieldCost * count
        }
    }

    func recommendedLimit(upTo maximumCost: Int) -> Int {
        let templateCost = Float(nodeCost)
        if templateCost == 0 {
            return 100
        }
        let estimatedBatchSize = (Float(maximumCost) / templateCost).rounded(.down)
        return min(100, max(1, Int(estimatedBatchSize)))
    }

    private enum QueryFormat {
        case item, list, pagedList
    }

    public var queryText: String {
        let brackets = Lista<String>()
        let format: QueryFormat

        switch paging {
        case .none:
            format = .item

        case let .last(count):
            format = .list
            brackets.append("last: \(count)")

        case .max:
            format = .pagedList
            brackets.append("first: 100")
            if let lastCursor {
                brackets.append("after: \"\(lastCursor)\"")
            }

        case let .first(count, useCursor):
            brackets.append("first: \(count)")
            if useCursor {
                format = .pagedList
                if let lastCursor {
                    brackets.append("after: \"\(lastCursor)\"")
                }
            } else {
                format = .list
            }
        }

        for param in extraParams {
            if let value = param.value as? String, let firstChar = value.first, firstChar != "[", firstChar != "{" {
                brackets.append("\(param.name): \"\(value)\"")
            } else {
                brackets.append("\(param.name): \(param.value)")
            }
        }

        let query: String = if brackets.count > 0 {
            name + "(" + brackets.joined(separator: ", ") + ")"
        } else {
            name
        }

        let fieldsText = "__typename " + fields.map(\.queryText).joined(separator: " ")

        switch format {
        case .item:
            return query + " { " + fieldsText + " }"
        case .list:
            return query + " { edges { node { " + fieldsText + " } } }"
        case .pagedList:
            return query + " { edges { node { " + fieldsText + " } cursor } pageInfo { hasNextPage } }"
        }
    }

    public var fragments: Lista<Fragment> {
        let res = Lista<Fragment>()
        for field in fields {
            res.append(contentsOf: field.fragments)
        }
        return res
    }

    private func scanNode(_ node: TypedJson.Entry, query: Query, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws(TQL.Error) {
        let resolvedParent: Node?

        if let o = Node(jsonPayload: node, parent: parent, relationship: relationship) {
            try await query.perNodeBlock?(.node(o))
            resolvedParent = o

        } else {
            // we're a container, not an object, unwrap this level and recurse into it
            resolvedParent = parent
        }

        for field in fields {
            if let scannable = field as? Scanning {
                if scannable is Fragment {
                    try await scannable.scan(query: query, pageData: node, parent: resolvedParent, relationship: field.name, extraQueries: extraQueries)

                } else if let fieldData = node.potentialObject(named: scannable.name) {
                    try await scannable.scan(query: query, pageData: fieldData, parent: resolvedParent, relationship: field.name, extraQueries: extraQueries)
                }
            }
        }
    }

    private func scanEdges(_ edges: [TypedJson.Entry], pageInfo: TypedJson.Entry?, query: Query, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws(TQL.Error) {
        do {
            for node in edges.compactMap({ $0.potentialObject(named: "node") }) {
                try await scanNode(node, query: query, parent: parent, relationship: relationship, extraQueries: extraQueries)
            }

            if let latestCursor = edges.last?.potentialString(named: "cursor"),
               let pageInfo, pageInfo.potentialBool(named: "hasNextPage") == true,
               let parentId = parent?.id {
                let newGroup = Group(cloning: self, lastCursor: latestCursor)
                if let shellRootElement = query.rootElement.asShell(for: newGroup, batchRootId: parentId) as? Scanning {
                    let nextPage = Query(from: query, with: shellRootElement)
                    extraQueries.append(nextPage)
                }
            }
        } catch TQL.Error.alreadyParsed {
            // exhausted new nodes
        }
    }

    private func scanList(nodes: [TypedJson.Entry], query: Query, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws(TQL.Error) {
        do {
            for node in nodes {
                try await scanNode(node, query: query, parent: parent, relationship: relationship, extraQueries: extraQueries)
            }
        } catch TQL.Error.alreadyParsed {
            // exhausted new nodes
        }
    }

    public func scan(query: Query, pageData: TypedJson.Entry, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws(TQL.Error) {
        if let nodes = pageData.potentialArray {
            try await scanList(nodes: nodes, query: query, parent: parent, relationship: relationship, extraQueries: extraQueries)

        } else {
            if let edges = pageData.potentialArray(named: "edges") {
                try await scanEdges(edges, pageInfo: pageData.potentialObject(named: "pageInfo"), query: query, parent: parent, relationship: relationship, extraQueries: extraQueries)
            } else {
                do {
                    try await scanNode(pageData, query: query, parent: parent, relationship: relationship, extraQueries: extraQueries)
                } catch TQL.Error.alreadyParsed {
                    // not a new node, ignore
                }
            }
        }
        if extraQueries.count > 0 {
            await TQL.log("\(query.logPrefix)(Group: \(name)) will need further paging: \(extraQueries.count) new queries")
        }
    }
}
