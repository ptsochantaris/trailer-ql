import Foundation
import Testing
@testable import TrailerQL

/// Offline tests: these feed canned payloads straight into the scanner, so they don't touch the
/// network like the example tests do.
@Suite("Scanning")
struct ScanningTests {
    /// Records what the scan reported, so a schema's output can be compared against another's.
    @Query.NodeActor
    final class Recorder {
        private(set) var countsByType = [String: Int]()
        private(set) var relationships = [String]()

        func record(_ output: ParseOutput) {
            guard case let .node(node) = output else {
                return
            }
            countsByType[node.elementType, default: 0] += 1
            if let relationship = node.relationship {
                relationships.append("\(node.parent?.elementType ?? "-")/\(relationship)/\(node.elementType)")
            }
        }
    }

    private static let labelFragment = Fragment(on: "Label") {
        Field.id
        Field("name")
    }

    private static var labelsGroup: Group {
        Group("labels", paging: .first(count: 10, paging: false)) { labelFragment }
    }

    /// A response for a batched query over one pull request that carries two labels.
    private static let payload = Data("""
    {"data":{"nodes":[{"__typename":"PullRequest","id":"PR_1","title":"A change","labels":{"edges":[
      {"node":{"__typename":"Label","id":"LA_1","name":"bug"}},
      {"node":{"__typename":"Label","id":"LA_2","name":"enhancement"}}
    ]}}]}}
    """.utf8)

    private func scan(_ fragment: Fragment) async throws -> Recorder {
        let recorder = Recorder()
        let template = Group("items") { fragment }
        let root = BatchGroup(name: "nodes", templateGroup: template, idList: ["PR_1"])
        let query = Query(name: "Test", rootElement: root, checkRate: false) { output in
            recorder.record(output)
        }
        let json = try #require(try Self.payload.asTypedJson())
        _ = try await query.processResponse(from: json)
        return recorder
    }

    @Test("A group inside a fragment is scanned")
    func groupInsideFragment() async throws {
        let recorder = try await scan(Fragment(on: "PullRequest") {
            Field.id
            Self.labelsGroup
        })

        #expect(await recorder.countsByType == ["PullRequest": 1, "Label": 2])
    }

    /// A fragment spread is flattened into the enclosing object by the server, so the scan has to
    /// look for a nested fragment's contents in that same object rather than in a field named after
    /// it. Getting this wrong silently dropped every node below the nested fragment.
    @Test("A group inside a nested fragment is scanned too")
    func groupInsideNestedFragment() async throws {
        let recorder = try await scan(Fragment(on: "PullRequest") {
            Field.id
            Fragment(on: "PullRequest") {
                Self.labelsGroup
            }
        })

        #expect(await recorder.countsByType == ["PullRequest": 1, "Label": 2])
    }

    @Test("Nesting a fragment does not change what the scan reports")
    func nestingMakesNoDifference() async throws {
        let direct = try await scan(Fragment(on: "PullRequest") {
            Field.id
            Self.labelsGroup
        })
        let nested = try await scan(Fragment(on: "PullRequest") {
            Field.id
            Fragment(on: "PullRequest") {
                Self.labelsGroup
            }
        })

        #expect(await direct.countsByType == nested.countsByType)
        #expect(await direct.relationships == nested.relationships)
    }

    /// Fragment declarations used to be emitted in `Set` iteration order, which is seeded per
    /// instance, so the same query could serialise differently from one call to the next.
    @Test("Query text is identical on every call")
    func queryTextIsStable() throws {
        let query = Query(name: "Test", rootElement: Group("pullRequests", paging: .first(count: 10, paging: true)) {
            Fragment(on: "PullRequest") {
                Field.id
                Group("author") {
                    Fragment(on: "User") {
                        Field.id
                        Field("login")
                    }
                    Fragment(on: "Bot") {
                        Field.id
                        Field("login")
                    }
                }
                Self.labelsGroup
            }
        }, checkRate: false)

        let first = query.queryText
        #expect(first.contains("fragment "))
        for _ in 0 ..< 20 {
            #expect(query.queryText == first)
        }
    }

    @Test("Every declared fragment appears exactly once")
    func fragmentsAreDeclaredOnce() throws {
        let shared = Fragment(on: "User") {
            Field.id
            Field("login")
        }
        // The same fragment reached by two different routes should still be declared once.
        let query = Query(name: "Test", rootElement: Group("pullRequests") {
            Fragment(on: "PullRequest") {
                Field.id
                Group("author") { shared }
                Group("mergedBy") { shared }
            }
        }, checkRate: false)

        let declarations = query.queryText.components(separatedBy: "fragment \(shared.name) on")
        #expect(declarations.count == 2, "expected one declaration, found \(declarations.count - 1)")
    }
}
