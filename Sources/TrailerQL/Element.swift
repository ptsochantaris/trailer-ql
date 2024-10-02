import Foundation
import Lista

public protocol Element: Sendable {
    var id: UUID { get }
    var name: String { get }
    var queryText: String { get }
    var fragments: Lista<Fragment> { get }
    var nodeCost: Int { get }

    func asShell(for element: Element, batchRootId: String?) -> Element?
}
