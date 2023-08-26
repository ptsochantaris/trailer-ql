@testable import TrailerQL
import XCTest

final class TrailerQLTests: XCTestCase {
    // Let's see where Rick and Morty currently are...
    private let url = URL(string: "https://rickandmortyapi.com/graphql")!

    override func setUp() async throws {
        // Reset our primitive mock DB
        Character.all.removeAll()
    }

    func testExampleLiveQuery() async throws {
        // Let's contruct our query schema. We want to create this GraphQL query:
        //
        // characters(filter: { name: "Rick" }) {
        //     results {
        //         id
        //         name
        //         status
        //         location {
        //             id
        //             name
        //             type
        //         }
        //     }
        // }

        let schema = Group("characters", ("filter", "{ name: \"Rick\" }")) {
            Group("results") {
                Field.id
                Field("name")
                Field("status")
                Group("location") {
                    Field.id
                    Field("name")
                    Field("type")
                }
            }
        }

        // We create a Query, and assign that schema as the root element. In this case we also
        // want to disable the GitHub-style rate check, which this API server doesn't support.
        // The Query initialiser has a lot of options, so be sure to check it out in more detail.

        let query = Query(name: "Rick And Morty", rootElement: schema, checkRate: false, perNode: scanNode)

        // TrailerQL now produces the GraphQL query above as text for us in `query.queryText`

        let queryText = query.queryText
        XCTAssert(queryText == " { characters(filter: { name: \"Rick\" }) { __typename results { __typename id name status location { __typename id name type } } } }")

        // Let's turn this into JSON to send to the API endpoint by encoding the query
        // text into a JSON object whose key is "query", and turn it into bytes
        let dataToSend = try JSONSerialization.data(withJSONObject: ["query": queryText])

        // Post it to the API, making sure the API knows this is JSON
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataToSend
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Let's get and parse the response as a JSON object
        let result = try await URLSession.shared.data(for: request).0
        let resultJson = try JSONSerialization.jsonObject(with: result)

        // And feed it into TrailerQL
        _ = try await query.processResponse(from: resultJson)

        // Sanity check that we did fetch stuff
        XCTAssertFalse(Character.all.isEmpty)

        // Let's list them out!
        print("\nAnd here they are, all \(Character.all.count) of them!")
        for character in Character.all {
            print(character.id, character.description, separator: "\t")
        }

        // Buuuuurp
        print()
    }

    private func scanNode(_ output: ParseOutput) {
        // This closure is called once for every item which is parsed by TrailerQL when it is
        // provided with the API response from the API endpoint. We'll see how to do that below.
        // Each call has a single parameter of type ParseOutput that reports on the progress of the
        // parsing.

        switch output {
        case .queryComplete:
            print("All nodes from the query received")

        case .queryPageComplete:
            print("All nodes from returned page of the query are received")

        case let .node(scannedNode):
            // Node contains various info on the parsed GraphQL object, such as its type, its ID and the ID of its
            // parent, if that exists. TrailerQL will _not_ parse nodes that don't contain an ID, but it will
            // happily "unwrap" layers to find items inside them. For example the "characters" group above
            // is not an object but a container, whereas "results" is a list of objects that contain ids.

            // We check `scannedNode.elementType` to know which type this callback is about, and then
            // instantiate each object with it. Internally those initialisers use the `.jsonPayload`
            // property to access the node's JSON and de-serialise an instance from it.

            switch scannedNode.elementType {
            case "Character":
                if let newCharacter = Character(from: scannedNode) {
                    Character.all.append(newCharacter)
                } else {
                    print("Could not parse character from: \(scannedNode.jsonPayload)")
                }
            case "Location":
                if let newLocation = Location(from: scannedNode) {
                    // A location object, in the schema for this API endpoint, belongs to
                    // a Character - i.e. each Character as a Location associated with it.
                    // So now that we have created a location object, we check the `.parent`
                    // property of the scanned node to see if we can find a `Character` instance
                    // this belongs to and add it there.

                    if let parentId = scannedNode.parent?.id,
                       let character = Character.find(id: parentId) {
                        character.location = newLocation
                    }
                } else {
                    print("Could not parse location from: \(scannedNode.jsonPayload)")
                }
            default:
                print("Unknown type: \(scannedNode.elementType)")
            }
        }
    }

    func testExampleLiveQueryWithFragments() async throws {
        let characterFragment = Fragment(on: "Character") {
            Field.id
            Field("name")
            Field("status")
        }

        let locationFragment = Fragment(on: "Location") {
            Field.id
            Field("name")
            Field("type")
        }

        let schema = Group("characters", ("filter", "{ name: \"Rick\" }")) {
            Group("results") {
                characterFragment
                Group("location") {
                    locationFragment
                }
            }
        }

        let query = Query(name: "Rick And Morty", rootElement: schema, checkRate: false, perNode: scanNode)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query.queryText])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let result = try await URLSession.shared.data(for: request).0
        let resultJson = try JSONSerialization.jsonObject(with: result)
        _ = try await query.processResponse(from: resultJson)

        print("\nAnd here they are, all \(Character.all.count) of them!")
        for character in Character.all {
            print(character.id, character.description, separator: "\t")
        }
    }

    func testExampleLiveQueryIds() async throws {
        //  fragment characterFragment on Character {
        //      id
        //      name
        //      status
        //      location {
        //          id
        //          name
        //          type
        //      }
        //  }
        //
        //  {
        //      charactersByIds(ids: [1,8,15,19]) {
        //          ... characterFragment
        //      }
        //  }

        let queries = Query.batching("Rick And Morty", groupName: "charactersByIds", idList: ["1", "2", "3", "4", "5"], checkRate: false, perNode: scanNode) {
            Fragment(on: "Character") {
                Field.id
                Field("name")
                Field("status")
                Group("location") {
                    Field.id
                    Field("name")
                    Field("type")
                }
            }
        }

        let firstQuery = queries.first!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": firstQuery.queryText])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let result = try await URLSession.shared.data(for: request).0
        let resultJson = try JSONSerialization.jsonObject(with: result)
        _ = try await firstQuery.processResponse(from: resultJson)

        print("\nAnd here they are, all \(Character.all.count) of them!")
        for character in Character.all {
            print(character.id, character.description, separator: "\t")
        }
        print()
    }
}
