import Foundation

public protocol Scanning: Element {
    func scan(query: Query, pageData: Any, parent: Node?, extraQueries: List<Query>) async throws
}
