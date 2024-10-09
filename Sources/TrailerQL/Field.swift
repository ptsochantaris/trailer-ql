import Foundation
import Lista

public struct Field: Element {
    public static let id = Field("id")

    public let id = UUID()
    public let name: String
    public var queryText: String { name }
    public let fragments = TQL.emptyList
    public var nodeCost: Int { 0 }

    public init(_ name: String) {
        self.name = name
    }

    public func asShell(for element: Element, batchRootId _: String?) -> Element? {
        if element.id == id {
            element
        } else {
            nil
        }
    }
}
