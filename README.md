TrailerQL
=========

## About
TrailerQL is a Swift package that simplifies many of the steps involved in querying a GraphQL endpoint.

- Type-safe creation of queries using element builder syntax
- Highly optimised scanning and parsing of returned data with callbacks
- Fully implemented in async/await
- Used in production apps to query and parse GitHub endpoints.

Currently used in [Trailer](https://github.com/ptsochantaris/trailer) and [Trailer-CLI](https://github.com/ptsochantaris/trailer-cli)

## Example (see `TrailerQLTests.swift` for complete code)
Let's see where Rick and Morty currently are...
```
let url = URL(string: "https://rickandmortyapi.com/graphql")!
```
Let's construct our query schema. Based on the documentation from that site, we want to create this GraphQL query:
```
characters(filter: { name: "Rick" }) {
    results {
        id
        name
        status
        location {
            id
            name
            type
        }
    }
}
```
In TrailerQL we build GraphQL object relationships using `Group`, `Field`, `Fragment` and `BatchGroup`. We start by declaring the top-level group, and give it the name `characters`. We also provide a tuple (or more, if needed) which contains parameter names and values. In this case we make the whole `{ name: "Rick" }` bit a parameter value for `filter`.
```
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
```
We create a Query, and assign that schema as the root element. In this case we also want to disable the GitHub-style rate check, which this API server doesn't support. The Query initialiser has a lot of options, so be sure to check it out in more detail.

The initialiser takes a closure which is called once for every item parsed by TrailerQL when it is provided with the API response data. We'll see how to do that below.
```        
let query = Query(name: "Rick And Morty", rootElement: schema, checkRate: false) { scannedNode in
    ...see below...
}
```
Each call to it takes a single parameter (called `scannedNode` in this example) of type `Node`. This class contains various info on the parsed GraphQL object, such as its type, its ID, and the ID of its parent, if that exists.

TrailerQL will _not_ parse nodes that don't contain an ID, but it will happily "unwrap" layers to find items inside them. For example the "characters" group above is not an object but a container, whereas "results" is a list of objects that contain ids.
```            
    switch scannedNode.elementType {
    case "Character":
        if let newCharacter = Character(from: scannedNode) {
            Character.all.append(newCharacter)
        }
    case "Location":
        if let newLocation = Location(from: scannedNode) {
```
Each `Character` has a `Location` associated with it in this endpoint's schema. So now that we have created a `Location`, we check the `.parent` property of the scanned `Node` to see if we can find a `Character` instance and add it there.
```
            if let parentId = scannedNode.parent?.id,
               let character = Character.find(id: parentId) {
                character.location = newLocation
            }
        }
    default:
        print("Unknown type: \(scannedNode.elementType)")
    }
```
We check `scannedNode.elementType` to know which type this callback is about, and then instantiate each object with it. Internally those initialisers use the `.jsonPayload` property of `Node` to access the node's JSON and de-serialise an instance from it.
        
TrailerQL's `Query` instance now produces the GraphQL query that we wanted to create as text for us, in `query.queryText`
```
let queryText = query.queryText

XCTAssert(queryText == " { characters(filter: { name: \"Rick\" }) { __typename results { __typename id name status location { __typename id name type } } } }")
```
Let's turn this into JSON to send to the API endpoint by encoding the query text into a JSON object whose key is "query", and turn it into bytes. (Any JSON encoder will do, in this example we're using the default Apple framework).
```
let dataToSend = try JSONSerialization.data(withJSONObject: ["query": queryText])
```        
Post it to the API, making sure the API knows this is JSON
```
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.httpBody = dataToSend
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
let result = try await URLSession.shared.data(for: request).0
```
Let's parse the response as a JSON object...
```
let resultJson = try JSONSerialization.jsonObject(with: result)
```
...and feed it intro TrailerQL. The `processResponse` method will run and invoke the callback we created above for every node it encounters.
```
_ = try await query.processResponse(from: resultJson)
```
In large queries, results may indicate that more paging is needed. If this occurs, the method will return a sequence of `Query` objects, which can be run to fetch more nodes. 

It's worth noting that running those queries can then return more `Query` objects and so on, as long as more data is available.

TrailerQL will attempt to create as few queries as possible in this case but stay below the maximum node limit of the API endpoint.

Let's list out any `Character` objects we parsed!
```
for character in Character.all {
    print(character.id, character.description, separator: "\t")
}
```

## Fragments
You can use GraphQL fragments with `Fragment`. For instance the query above could be written as:
```
fragment locationFragment on Location { 
    id
    name
    type
}

fragment characterFragment on Character {
    id
    name
    status
}

{ 
    characters(filter: { name: "Rick" }) { 
        results { 
            ... characterFragment
            location { 
                ... locationFragment
            }
        }
    }
}
```
Which in TrailerQL would be expressed like this:
```
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
```

In this example this is actually more complicated and not very useful, but for cases where we need to query the same type in various places, fragments both increase the speed of the query and also make it far easier to keep the schema uniform and readable. Picture how better this would make things if there were more groups that expected `Character`s or `Location`s for instance.

## Batches
Sometimes we don't want to query a single scema, but instead we want to query a bunch of items of the same type. A `BatchGroup` lets us do this by spreading a fragment over a series of Ids.

```
let characterAndLocation = Group("items") {
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
```
Let's say we want to query the known IDs for a bunch of characters.
```
{
    charactersByIds(ids: [1,2,3,4,5]) {
        ... characterFragment
    }
}
```
On TrailerQL the above would be generated like this...
```
let batch = BatchGroup(name: "charactersByIds", templateGroup: characterAndLocation, idList: ["1", "2", "3", "4", "5"])
```
...and then passed as the root element of the `Query`...
```
let query = Query(name: "Rick And Morty", rootElement: batch, checkRate: false, perNode: scanNode)
```
...and run the Query as before.

## License
Copyright (c) 2023 Paul Tsochantaris. Licensed under the MIT License, see LICENSE for details.