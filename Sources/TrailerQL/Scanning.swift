import Foundation
import Lista
import TrailerJson

public protocol Scanning: Element {
    func scan(query: Query, pageData: TypedJson.Entry, parent: Node?, relationship: String?, extraQueries: Lista<Query>) async throws(TQL.Error)
}
