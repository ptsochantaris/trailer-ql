import Foundation
import Lista

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
        name = cloning.name
        type = cloning.type
        self.elements = elements
    }

    public init(on type: String, @ElementsBuilder elements: () -> [Element]) {
        id = UUID()
        name = type.lowercased() + "Fragment"
        self.type = type
        self.elements = elements()
    }

    public func addingElement(_ element: Element) -> Fragment {
        var currentElements = elements
        currentElements.append(element)
        return Fragment(cloning: self, elements: currentElements)
    }

    public func scan(query: Query, pageData: Any, parent: Node?, extraQueries: Lista<Query>) async throws {
        // DLog("\(query.logPrefix)Scanning fragment \(name)")
        guard let hash = pageData as? JSON else { return }

        for element in elements {
            if let scannable = element as? Scanning, let elementData = hash[element.name] {
                try await scannable.scan(query: query, pageData: elementData, parent: parent, extraQueries: extraQueries)
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
