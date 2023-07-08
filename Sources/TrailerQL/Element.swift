import Foundation

public protocol Element {
    var id: UUID { get }
    var name: String { get }
    var queryText: String { get }
    var fragments: List<Fragment> { get }
    var nodeCost: Int { get }

    func asShell(for element: Element, batchRootId: String?) -> Element?
}
