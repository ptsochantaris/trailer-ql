import Foundation
import TrailerJson

/// A child element that needs scanning, with every decision that doesn't depend on the payload
/// already made.
///
/// Working this out per node meant a dynamic cast for each of a node's fields, repeated for every
/// node in every page, even though an element tree never changes after it is built. Resolving it
/// once at construction leaves the scan with a plain array to walk.
struct ScanTarget: Sendable {
    let element: any Scanning
    let name: String
    /// Fragments are scanned against the payload of the node that encloses them, rather than
    /// against a field named after them.
    let scansEnclosingPayload: Bool

    /// Resolves the scannable children of a group, honouring the fragment distinction above.
    static func resolvingFragments(in elements: [Element]) -> [ScanTarget] {
        elements.compactMap { element in
            guard let scannable = element as? Scanning else {
                return nil
            }
            return ScanTarget(element: scannable, name: element.name, scansEnclosingPayload: scannable is Fragment)
        }
    }

    /// Resolves the scannable children of a fragment, all of which are looked up by name.
    ///
    /// Note that this means a fragment nested directly inside another fragment is not scanned, since
    /// no payload carries a field named after a generated fragment name. Groups are what nest in
    /// practice, so this preserves existing behaviour rather than quietly changing it.
    static func byName(in elements: [Element]) -> [ScanTarget] {
        elements.compactMap { element in
            guard let scannable = element as? Scanning else {
                return nil
            }
            return ScanTarget(element: scannable, name: element.name, scansEnclosingPayload: false)
        }
    }
}
