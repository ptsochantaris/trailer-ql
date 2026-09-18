import Foundation
import Lista
import TrailerJson

public struct Fragment: Scanning, Hashable {
    public let id: UUID
    public let name: String

    private let elements: [Element]
    private let type: String
    private let scanTargets: [ScanTarget]

    /// Built at construction: deriving the name already has to assemble the element text, so the
    /// declaration comes out of the same pass rather than being rebuilt on each access.
    let declaration: String

    /// Every fragment below this one, flattened at construction. This fragment itself is prepended
    /// by ``fragments``, since it cannot be referenced while it is still being built.
    private let descendantFragments: [Fragment]

    public var nodeCost: Int {
        elements.reduce(0) { $0 + $1.nodeCost }
    }

    public var queryText: String {
        "... \(name)"
    }

    public func asShell(for element: Element, batchRootId _: String?) -> Element? {
        if element.id == id {
            return element
        }

        var elementsToKeep = elements.compactMap { $0.asShell(for: element, batchRootId: nil) }
        if elementsToKeep.isEmpty {
            return nil
        }
        if let idField = elements.first(where: { $0.name == Field.id.name }) {
            elementsToKeep.append(idField)
        }
        return Fragment(cloning: self, elements: elementsToKeep)
    }

    public var fragments: Lista<Fragment> {
        let res = Lista<Fragment>(value: self)
        res.append(from: descendantFragments)
        return res
    }

    private init(cloning: Fragment, elements: [Element]) {
        self.init(id: cloning.id, type: cloning.type, elements: elements)
    }

    public init(on type: String, @ElementsBuilder elements: () -> [Element]) {
        self.init(id: UUID(), type: type, elements: elements())
    }

    private init(id: UUID, type: String, elements: [Element]) {
        self.id = id
        self.type = type
        self.elements = elements
        scanTargets = ScanTarget.resolvingFragments(in: elements)

        // One pass over the element text serves both the name and the declaration.
        let parts = elements.map(\.queryText)
        let name = Fragment.makeName(on: type, parts: parts)
        self.name = name
        declaration = parts.assembled(prefix: "fragment \(name) on \(type) { __typename ", suffix: " }")

        var collected = [Fragment]()
        for element in elements {
            collected.append(contentsOf: element.fragments)
        }
        descendantFragments = collected
    }

    // Derives a stable name from the fragment's type and contents, so that distinct
    // fragments on the same type get distinct GraphQL names while identical ones de-dupe.
    private static func makeName(on type: String, parts: [String]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        mix(type)
        for part in parts {
            mix("\u{0}")
            mix(part)
        }
        return type.lowercased() + "Fragment" + String(hash, radix: 16)
    }

    public func addingElement(_ element: Element) -> Fragment {
        var currentElements = elements
        currentElements.append(element)
        return Fragment(cloning: self, elements: currentElements)
    }

    public func scan(query: Query, pageData: TypedJson.Entry, parent: Node?, relationship _: String?, extraQueries: Lista<Query>) async throws(TQL.Error) {
        // DLog("\(query.logPrefix)Scanning fragment \(name)")

        for target in scanTargets {
            if target.scansEnclosingPayload {
                // A nested fragment is a spread: the server merges its fields into this same
                // object, so there is no field named after it to descend into.
                try await target.element.scan(query: query, pageData: pageData, parent: parent, relationship: target.name, extraQueries: extraQueries)

            } else if let elementData = pageData.potentialObject(named: target.name) {
                try await target.element.scan(query: query, pageData: elementData, parent: parent, relationship: target.name, extraQueries: extraQueries)
            }
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    public static func == (lhs: Fragment, rhs: Fragment) -> Bool {
        lhs.name == rhs.name
    }
}
