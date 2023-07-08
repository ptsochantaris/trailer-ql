import Foundation

public protocol Scanning: Element {
    func scan(query: TrailerQL.Query, pageData: Any, parent: TrailerQL.Node?, extraQueries: LinkedList<TrailerQL.Query>) async throws
}
