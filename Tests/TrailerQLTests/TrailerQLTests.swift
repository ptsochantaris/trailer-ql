import XCTest
@testable import TrailerQL

protocol Stuff {
    var id: String { get }
    static var all: [Self] { get }
}

extension Stuff {
    static func item(for id: String) -> Self? {
        all.first { $0.id == id }
    }
}

final class Location: Stuff {
    static var all = [Location]()

    let id: String
    let name: String
    let type: String
    
    init?(from node: Node) {
        guard let name = node.jsonPayload["name"] as? String,
              let type = node.jsonPayload["type"] as? String
        else {
            return nil
        }
        self.id = node.id
        self.name = name
        self.type = type
    }
}

final class Character: Stuff {
    static var all = [Character]()

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
        self.id = node.id
        self.name = name
        self.status = status
    }
    
    var description: String {
        if let location {
            return name + ", from " + location.name
        } else {
            return name
        }
    }
}

final class TrailerQLTests: XCTestCase {
    func testLiveQuery() async throws {
        
        let root = Group("characters", ("filter", "{ name: \"Rick\" }")) {
            Group("results") {
                TQL.idField
                Field("name")
                Field("status")
                Group("location") {
                    TQL.idField
                    Field("name")
                    Field("type")
                }
            }
        }
        
        let query = Query(name: "Rick And Morty", rootElement: root, checkRate: false) { scannedNode in
            switch scannedNode.elementType {
            case "Character":
                if let newCharacter = Character(from: scannedNode) {
                    Character.all.append(newCharacter)
                }
            case "Location":
                if let newLocation = Location(from: scannedNode) {
                    Location.all.append(newLocation)
                    if let parentId = scannedNode.parent?.id,
                       let character = Character.item(for: parentId) {
                        character.location = newLocation
                    }
                }
            default:
                print("Unknown type: \(scannedNode.elementType)")
            }
        }
        
        let queryText = query.queryText
        XCTAssert(queryText == " { characters(filter: { name: \"Rick\" }) { __typename results { __typename id name status location { __typename id name type } } } }")
        
        let url = URL(string: "https://rickandmortyapi.com/graphql")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": queryText])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let result = try await URLSession.shared.data(for: request).0
        let resultJson = try JSONSerialization.jsonObject(with: result)
        _ = try await query.processResponse(from: resultJson)
        
        XCTAssertFalse(Character.all.isEmpty)
        XCTAssertFalse(Location.all.isEmpty)

        print("\nAnd here they are, all \(Character.all.count) of them!")
        for character in Character.all {
            print(character.id, character.description, separator: "\t")
        }
        print()
    }
}
