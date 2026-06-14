import Foundation
import Lista
import TrailerJson

public struct Fragment: Scanning, Hashable {
    public let id: UUID
    public let name: String

    private let elements: [Element]
    private let type: String

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

    var declaration: String {
        "fragment \(name) on \(type) { __typename " + elements.map(\.queryText).joined(separator: " ") + " }"
    }

    public var fragments: Lista<Fragment> {
        let res = Lista<Fragment>(value: self)
        for element in elements {
            res.append(contentsOf: element.fragments)
        }
        return res
    }

    private init(cloning: Fragment, elements: [Element]) {
        id = cloning.id
        type = cloning.type
        self.elements = elements
        name = Fragment.makeName(on: cloning.type, elements: elements)
    }

    public init(on type: String, @ElementsBuilder elements: () -> [Element]) {
        id = UUID()
        self.type = type
        self.elements = elements()
        name = Fragment.makeName(on: type, elements: self.elements)
    }

    // Derives a stable name from the fragment's type and contents, so that distinct
    // fragments on the same type get distinct GraphQL names while identical ones de-dupe.
    private static func makeName(on type: String, elements: [Element]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        mix(type)
        for element in elements {
            mix("\u{0}")
            mix(element.queryText)
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

        for element in elements {
            if let scannable = element as? Scanning, let elementData = pageData.potentialObject(named: element.name) {
                try await scannable.scan(query: query, pageData: elementData, parent: parent, relationship: element.name, extraQueries: extraQueries)
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
