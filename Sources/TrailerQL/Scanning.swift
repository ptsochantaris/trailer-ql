import Foundation
import Lista

public protocol Scanning: Element {
    func scan(query: Query, pageData: Any, parent: Node?, extraQueries: Lista<Query>) async throws
}
