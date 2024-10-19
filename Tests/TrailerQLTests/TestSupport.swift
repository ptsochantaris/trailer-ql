import Foundation
import Lista
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
        guard let name = node.jsonPayload.potentialString(named: "name"),
              let status = node.jsonPayload.potentialString(named: "status")
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
        guard let name = node.jsonPayload.potentialString(named: "name"),
              let type = node.jsonPayload.potentialString(named: "type")
        else {
            return nil
        }
        id = node.id
        self.name = name
        self.type = type
    }
}
