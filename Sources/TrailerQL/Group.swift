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
    private let scanTargets: [ScanTarget]

    /// The field list as query text, without the leading `__typename`. Everything this depends on
    /// is fixed at construction, and generating it walks the whole subtree, so it is built once
    /// here instead of on every access.
    let fieldsQueryText: String
    public let queryText: String

    /// Every fragment in this subtree, flattened at construction for the same reason: collecting
    /// them on demand meant walking the tree and allocating a list at each node it passed.
    private let allFragments: [Fragment]

    public init(_ name: String, _ params: Param..., paging: Paging = .none, @ElementsBuilder fields: () -> [Element]) {
        id = UUID()
        self.name = name
        let fields = fields()
        self.fields = fields
        self.paging = paging
        extraParams = params
        lastCursor = nil
        scanTargets = ScanTarget.resolvingFragments(in: fields)
        fieldsQueryText = Group.makeFieldsQueryText(fields)
        queryText = Group.makeQueryText(name: name, paging: paging, extraParams: params, lastCursor: nil, fieldsQueryText: fieldsQueryText)
        allFragments = Group.collectFragments(in: fields)
    }

    private init(cloning group: Group, name: String? = nil, lastCursor: String? = nil, replacedFields: [Element]? = nil) {
        id = group.id
        let name = name ?? group.name
        self.name = name
        let fields = replacedFields ?? group.fields
        self.fields = fields
        paging = group.paging
        extraParams = group.extraParams
        self.lastCursor = lastCursor

        if let replacedFields {
            scanTargets = ScanTarget.resolvingFragments(in: replacedFields)
            fieldsQueryText = Group.makeFieldsQueryText(replacedFields)
            allFragments = Group.collectFragments(in: replacedFields)
        } else {
            scanTargets = group.scanTargets
            fieldsQueryText = group.fieldsQueryText
            allFragments = group.allFragments
        }
        queryText = Group.makeQueryText(name: name, paging: group.paging, extraParams: group.extraParams, lastCursor: lastCursor, fieldsQueryText: fieldsQueryText)
    }

    private static func makeFieldsQueryText(_ fields: [Element]) -> String {
        // Materialised first because `queryText` is computed for some element kinds, so asking for
        // it once per field is cheaper than asking again while sizing the buffer.
        fields.map(\.queryText).assembled()
    }

    private static func collectFragments(in fields: [Element]) -> [Fragment] {
        var result = [Fragment]()
        for field in fields {
            result.append(contentsOf: field.fragments)
        }
        return result
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

    private static func makeQueryText(name: String, paging: Paging, extraParams: [Param], lastCursor: String?, fieldsQueryText: String) -> String {
        var brackets = [String]()
        brackets.reserveCapacity(extraParams.count + 2)
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

        let query: String = if brackets.isEmpty {
            name
        } else {
            brackets.assembled(separator: ", ", prefix: "\(name)(", suffix: ")")
        }

        // The `__typename` prefix is part of the opening text rather than being concatenated onto
        // the field list, so the field list is copied once instead of twice.
        let opening: String
        let closing: String
        switch format {
        case .item:
            opening = " { __typename "
            closing = " }"
        case .list:
            opening = " { edges { node { __typename "
            closing = " } } }"
        case .pagedList:
            opening = " { edges { node { __typename "
            closing = " } cursor } pageInfo { hasNextPage } }"
        }

        var text = String()
        text.reserveCapacity(query.utf8.count + opening.utf8.count + fieldsQueryText.utf8.count + closing.utf8.count)
        text += query
        text += opening
        text += fieldsQueryText
        text += closing
        return text
    }

    public var fragments: Lista<Fragment> {
        let res = Lista<Fragment>()
        res.append(from: allFragments)
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

        for target in scanTargets {
            if target.scansEnclosingPayload {
                try await target.element.scan(query: query, pageData: node, parent: resolvedParent, relationship: target.name, extraQueries: extraQueries)

            } else if let fieldData = node.potentialObject(named: target.name) {
                try await target.element.scan(query: query, pageData: fieldData, parent: resolvedParent, relationship: target.name, extraQueries: extraQueries)
            }
        }
    }

    private func scanEdges(_ edges: [TypedJson.Entry], pageInfo: TypedJson.Entry?, query: Query, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws(TQL.Error) {
        do {
            for edge in edges {
                guard let node = edge.potentialObject(named: "node") else {
                    continue
                }
                try await scanNode(node, query: query, parent: parent, relationship: relationship, extraQueries: extraQueries)
            }

            if let latestCursor = edges.last?.potentialString(named: "cursor"),
               let pageInfo, pageInfo.potentialBool(named: "hasNextPage") == true,
               let parentId = parent?.id {
                let newGroup = Group(cloning: self, lastCursor: latestCursor)
                if let shellRootElement = query.rootElement.asShell(for: newGroup, batchRootId: parentId) as? Scanning {
                    let nextPage = Query(from: query, with: shellRootElement)
                    extraQueries.append(nextPage)
                    await TQL.log("\(query.logPrefix)(Group: \(name)) will need paging for parent \(parentId)")
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
    }
}
