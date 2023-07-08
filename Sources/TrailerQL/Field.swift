import Foundation

public struct Field: Element {
    public let id = UUID()
    public let name: String
    public var queryText: String { name }
    public let fragments = TQL.emptyList
    public let nodeCost = 0
    
    public init(_ name: String) {
        self.name = name
    }
    
    public func asShell(for element: Element, batchRootId _: String?) -> Element? {
        if element.id == id {
            return element
        } else {
            return nil
        }
    }
}

