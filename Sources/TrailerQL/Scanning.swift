import Foundation
import Lista

public protocol Scanning: Element {
    func scan(query: Query, pageData: Any, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws
}
