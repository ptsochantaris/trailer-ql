import Foundation
@preconcurrency import Lista
@testable import TrailerQL

// Our, erm, heroes
final class Character {
    // Our minimalist database of characters :)
    static let all = Lista<Character>()
    static func find(id: String) -> Character? {
        all.first { $0.id == id }
    }

    let id: String
    let name: String
    let status: String
    var location: Location?

    init?(from node: Node) {
        guard let name = node.jsonPayload["name"] as? String,
              let status = node.jsonPayload["status"] as? String
        else {
            return nil
        }
        id = node.id
        self.name = name
        self.status = status
    }

    var description: String {
        if let location {
            name + ", from " + location.name
        } else {
            name
        }
    }
}

// A record that holds their location
final class Location {
    let id: String
    let name: String
    let type: String

    init?(from node: Node) {
        guard let name = node.jsonPayload["name"] as? String,
              let type = node.jsonPayload["type"] as? String
        else {
            return nil
        }
        id = node.id
        self.name = name
        self.type = type
    }
}
