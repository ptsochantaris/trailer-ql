import Foundation

extension Collection<String> {
    /// Joins the elements, wrapped in `prefix` and `suffix`, into a single buffer sized up front.
    ///
    /// Chaining `+` copies the accumulating string at every step, because the left operand arrives
    /// borrowed and so isn't uniquely referenced when the append needs to grow it. Going through
    /// `joined(separator:)` and then embedding the result copies it again. Sizing one buffer and
    /// appending each piece into it copies each piece exactly once.
    func assembled(separator: String = " ", prefix: String = "", suffix: String = "") -> String {
        var capacity = prefix.utf8.count + suffix.utf8.count
        let separatorCount = separator.utf8.count
        for element in self {
            capacity += element.utf8.count + separatorCount
        }

        var text = String()
        text.reserveCapacity(capacity)
        text += prefix
        var needsSeparator = false
        for element in self {
            if needsSeparator {
                text += separator
            } else {
                needsSeparator = true
            }
            text += element
        }
        text += suffix
        return text
    }
}
