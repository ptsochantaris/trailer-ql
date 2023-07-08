import Foundation

@resultBuilder
public enum ElementsBuilder {
    public static func buildBlock(_ components: Element...) -> [Element] {
        components
    }
    
    public static func buildBlock(_ components: [Element]...) -> [Element] {
        components.flatMap { $0 }
    }
    
    public static func buildArray(_ components: [Element]) -> [Element] {
        components
    }
    
    public static func buildArray(_ components: [[Element]]) -> [Element] {
        components.flatMap { $0 }
    }
    
    public static func buildOptional(_ component: [Element]?) -> [Element] {
        component ?? []
    }
    
    public static func buildPartialBlock(first: Element) -> [Element] {
        [first]
    }
    
    public static func buildPartialBlock(accumulated: [Element], next: Element) -> [Element] {
        var accumulated = accumulated
        accumulated.append(next)
        return accumulated
    }
    
    public static func buildPartialBlock(first: [Element]) -> [Element] {
        first
    }
    
    public static func buildPartialBlock(accumulated: [Element], next: [Element]) -> [Element] {
        accumulated + next
    }
}

