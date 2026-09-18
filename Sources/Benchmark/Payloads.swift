import Foundation

/// Response payloads for the benchmarks.
///
/// Two sources, for two different reasons:
///
/// - ``issues(repoCount:)`` amplifies `issueList.json`, a real captured GitHub response for
///   Trailer's "Open Issues" query, up to batch scale. Real data keeps the key distribution, the
///   escape sequences and the body-text sizes honest.
/// - ``accompanyingItems(prCount:)`` synthesises a response for the accompanying-items query,
///   which no capture covers. It is eight levels deep with paged connections at six of them, and
///   is generated from a fixed seed so every run scans exactly the same tree.
enum Payloads {
    // MARK: - Ids

    static func repoIds(count: Int) -> [String] {
        (0 ..< count).map { "R_kgDOAqwwJ\(idSuffix($0))" }
    }

    static func prIds(count: Int) -> [String] {
        (0 ..< count).map { "PR_kwDOAqwwJc6W\(idSuffix($0))" }
    }

    /// Node ids are base64-ish and never short, which is what makes them allocate when unescaped.
    private static func idSuffix(_ index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var value = index + 100_000
        var result = ""
        while value > 0 {
            result.append(alphabet[value % alphabet.count])
            value /= alphabet.count
        }
        return result
    }

    // MARK: - Real capture, amplified

    /// Repeats the captured repository node `repoCount` times, giving each copy its own id so the
    /// scan sees distinct parents (and so produces one paging continuation per repo, as it would
    /// against the real API).
    static func issues(repoCount: Int) throws -> Data {
        guard let url = Bundle.module.url(forResource: "issueList", withExtension: "json") else {
            throw Failure.missingResource
        }
        let original = try Data(contentsOf: url)

        guard let root = try JSONSerialization.jsonObject(with: original) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let nodes = data["nodes"] as? [[String: Any]],
              let template = nodes.first
        else {
            throw Failure.unexpectedCaptureShape
        }

        let ids = repoIds(count: repoCount)
        let amplified = ids.map { id -> [String: Any] in
            var copy = template
            copy["id"] = id
            return copy
        }

        var newData = data
        newData["nodes"] = amplified
        return try JSONSerialization.data(withJSONObject: ["data": newData])
    }

    // MARK: - Synthetic deep payload

    static func accompanyingItems(prCount: Int) -> Data {
        var random = Seeded(seed: 0x5EED_1234_ABCD_0001)
        var pullRequests = [String]()
        pullRequests.reserveCapacity(prCount)

        for index in 0 ..< prCount {
            pullRequests.append(pullRequest(index: index, random: &random))
        }

        let text = """
        {"data":{"nodes":[\(pullRequests.joined(separator: ","))],\(rateLimit)}}
        """
        return Data(text.utf8)
    }

    private static let rateLimit = #""rateLimit":{"limit":5000,"cost":1,"remaining":4499,"resetAt":"2024-10-19T23:12:52Z","nodeCount":1051}"#

    private static func pullRequest(index: Int, random: inout Seeded) -> String {
        let id = "PR_kwDOAqwwJc6W\(idSuffix(index))"

        let reviewRequests = (0 ..< random.next(upTo: 4)).map { position in
            let reviewer = switch position % 3 {
            case 0: user(index: index * 7 + position)
            case 1: mannequin(index: index * 7 + position)
            default: team(index: index * 7 + position)
            }
            return """
            {"__typename":"ReviewRequest","id":"RR_kwDOAqwwJc\(idSuffix(index * 13 + position))","requestedReviewer":\(reviewer)}
            """
        }

        let reviews = (0 ..< random.next(upTo: 6)).map { position in
            """
            {"__typename":"PullRequestReview","id":"PRR_kwDOAqwwJc\(idSuffix(index * 17 + position))","body":\(body(&random)),"state":"COMMENTED","createdAt":"2024-09-17T22:47:15Z","updatedAt":"2024-09-18T09:12:00Z","author":\(author(index: index * 17 + position))}
            """
        }

        let checkSuites = (0 ..< random.next(upTo: 3)).map { suite in
            let checkRuns = (0 ..< random.next(upTo: 5)).map { run in
                """
                {"__typename":"CheckRun","id":"CR_kwDOAqwwJc\(idSuffix(index * 23 + suite * 5 + run))","name":"build-and-test","conclusion":"SUCCESS","startedAt":"2024-09-18T00:00:11Z","completedAt":"2024-09-18T00:07:42Z","permalink":"https://github.com/ptsochantaris/trailer/runs/\(index)\(suite)\(run)"}
                """
            }
            return """
            {"__typename":"CheckSuite",\(edges(checkRuns, named: "checkRuns", cursorSeed: index * 31 + suite, hasNextPage: !checkRuns.isEmpty))}
            """
        }

        let contexts = (0 ..< random.next(upTo: 4)).map { position in
            """
            {"__typename":"StatusContext","id":"SC_kwDOAqwwJc\(idSuffix(index * 37 + position))","context":"ci/build","description":"Build finished","state":"SUCCESS","targetUrl":"https://example.com/build/\(index)/\(position)","createdAt":"2024-09-18T00:00:11Z"}
            """
        }

        // `commit` carries no id, so the scan unwraps it as a container rather than making a node.
        let commit = """
        {"__typename":"Commit",\(edges(checkSuites, named: "checkSuites", cursorSeed: index * 41, hasNextPage: !checkSuites.isEmpty)),"status":{"__typename":"Status","contexts":[\(contexts.joined(separator: ","))]}}
        """
        // `.last(count: 1)` paging means edges without cursors, so no continuation is queued here.
        let commitEdge = """
        {"edges":[{"node":{"__typename":"PullRequestCommit","commit":\(commit)}}]}
        """

        let reactions = (0 ..< random.next(upTo: 7)).map { position in
            """
            {"__typename":"Reaction","id":"REA_kwDOAqwwJc\(idSuffix(index * 43 + position))","content":"THUMBS_UP","createdAt":"2024-09-18T08:14:02Z","user":\(user(index: index * 43 + position))}
            """
        }

        let comments = (0 ..< random.next(upTo: 9)).map { position in
            """
            {"__typename":"IssueComment","id":"IC_kwDOAqwwJc\(idSuffix(index * 47 + position))","body":\(body(&random)),"url":"https://github.com/ptsochantaris/trailer/issues/1#issuecomment-\(index)\(position)","createdAt":"2024-09-18T08:20:00Z","updatedAt":"2024-09-18T08:21:00Z","author":\(author(index: index * 47 + position))}
            """
        }

        return """
        {"__typename":"PullRequest","id":"\(id)",\
        \(edges(reviewRequests, named: "reviewRequests", cursorSeed: index * 53, hasNextPage: reviewRequests.count > 2)),\
        \(edges(reviews, named: "reviews", cursorSeed: index * 59, hasNextPage: reviews.count > 3)),\
        "commits":\(commitEdge),\
        \(edges(reactions, named: "reactions", cursorSeed: index * 61, hasNextPage: reactions.count > 4)),\
        \(edges(comments, named: "comments", cursorSeed: index * 67, hasNextPage: comments.count > 5))}
        """
    }

    /// A paged connection: `name: { edges: [{ node, cursor }], pageInfo: { hasNextPage } }`.
    private static func edges(_ nodes: [String], named name: String, cursorSeed: Int, hasNextPage: Bool) -> String {
        let edgeTexts = nodes.enumerated().map { position, node in
            """
            {"node":\(node),"cursor":"Y3Vyc29yOnYyOpK5\(idSuffix(cursorSeed + position))"}
            """
        }
        return """
        "\(name)":{"edges":[\(edgeTexts.joined(separator: ","))],"pageInfo":{"hasNextPage":\(hasNextPage)}}
        """
    }

    private static func author(index: Int) -> String {
        index % 5 == 0 ? bot(index: index) : user(index: index)
    }

    private static func user(index: Int) -> String {
        """
        {"__typename":"User","id":"U_kgDOABfi\(idSuffix(index))","login":"contributor\(index)","avatarUrl":"https://avatars.githubusercontent.com/u/1565368?u=869a2af95711cc1c9698e71173be67188dfdeaf6&v=4"}
        """
    }

    private static func bot(index: Int) -> String {
        """
        {"__typename":"Bot","id":"BOT_kgDOABfi\(idSuffix(index))","login":"dependabot\(index)","avatarUrl":"https://avatars.githubusercontent.com/in/29110?v=4"}
        """
    }

    private static func mannequin(index: Int) -> String {
        """
        {"__typename":"Mannequin","id":"MAN_kgDOABfi\(idSuffix(index))","login":"migrated\(index)","avatarUrl":"https://avatars.githubusercontent.com/u/10137?v=4"}
        """
    }

    private static func team(index: Int) -> String {
        """
        {"__typename":"Team","id":"T_kwDOAqwwJc\(idSuffix(index))","slug":"reviewers-\(index)"}
        """
    }

    /// Bodies carry escapes and run to a few KB, as real issue and comment bodies do.
    private static func body(_ random: inout Seeded) -> String {
        let repeats = 1 + random.next(upTo: 6)
        var text = ""
        text.reserveCapacity(repeats * bodyParagraph.count)
        for _ in 0 ..< repeats {
            text += bodyParagraph
        }
        return "\"\(text)\""
    }

    private static let bodyParagraph = #"### Description\nI am getting a crash on Swift 6.0 where all works fine on 5.9, it can be related to @sendable.\n\n```swift\nextension Notification: @unchecked @retroactive Sendable {}\n```\n\nSee the \"reproduction\" section below, and the attached log — the stack is truncated.\n"#

    // MARK: - Support

    enum Failure: Error {
        case missingResource, unexpectedCaptureShape
    }

    /// A fixed-seed generator, so payload shape is identical from run to run.
    private struct Seeded {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next(upTo bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }
}
