import TrailerQL

/// The element trees used by the benchmarks.
///
/// These mirror the schemas that Trailer itself builds in `GraphQL.swift`, field for field, so the
/// numbers here reflect the shapes TrailerQL actually sees in production rather than a toy query.
/// `issuesBatch` in particular matches the captured `issueList.json` response exactly.
enum Schemas {
    // MARK: - Shared leaves

    private static let nameWithOwnerField = Field("nameWithOwner")

    private static let userFragment = Fragment(on: "User") {
        Field.id
        Field("login")
        Field("avatarUrl")
    }

    private static let mannequinFragment = Fragment(on: "Mannequin") {
        Field.id
        Field("login")
        Field("avatarUrl")
    }

    /// Two fragments on one group: both get scanned against every author payload, which is the
    /// multi-fragment dispatch case.
    private static let authorGroup = Group("author") {
        userFragment
        Fragment(on: "Bot") {
            Field.id
            Field("login")
            Field("avatarUrl")
        }
    }

    private static let milestoneFragment = Fragment(on: "Milestone") {
        Field("title")
    }

    private static let labelFragment = Fragment(on: "Label") {
        Field.id
        Field("name")
        Field("color")
        Field("createdAt")
        Field("updatedAt")
    }

    /// Trailer's `smallPageSize` / `largePageSize` at the default sync profile.
    private static let smallPage = Group.Paging.first(count: 10, paging: true)
    private static let largePage = Group.Paging.first(count: 50, paging: true)

    private static func commentGroup(for typeName: String) -> Group {
        Group("comments", paging: largePage) {
            Fragment(on: typeName) {
                Field.id
                Field("body")
                Field("url")
                Field("createdAt")
                Field("updatedAt")
                authorGroup
            }
        }
    }

    // MARK: - Issue list (matches issueList.json)

    private static var issueFragment: Fragment {
        Fragment(on: "Issue") {
            Field.id
            Field("bodyText")
            Field("state")
            Field("createdAt")
            Field("updatedAt")
            Field("number")
            Field("title")
            Field("url")
            Group("milestone") { milestoneFragment }
            authorGroup
            Group("assignees", paging: smallPage) { userFragment }
            Group("labels", paging: smallPage) { labelFragment }
        }
    }

    /// `Fragment(on: "Repository") { id, issues(states: [OPEN]) { ...issueFragment } }`
    private static var allOpenIssuesFragment: Fragment {
        Fragment(on: "Repository") {
            Field.id
            Group("issues", ("states", "[OPEN]"), paging: largePage) {
                issueFragment
            }
        }
    }

    // MARK: - Accompanying items (the deep one)

    /// Trailer's `update(for:steps:)` fragment with every sync step enabled: eight levels deep,
    /// with fragments at four of them and paged connections at six.
    private static var accompanyingPrFragment: Fragment {
        Fragment(on: "PullRequest") {
            Field.id

            Group("reviewRequests", paging: smallPage) {
                Fragment(on: "ReviewRequest") {
                    Field.id
                    Group("requestedReviewer") {
                        userFragment
                        mannequinFragment
                        Fragment(on: "Team") {
                            Field.id
                            Field("slug")
                        }
                    }
                }
            }

            Group("reviews", paging: smallPage) {
                Fragment(on: "PullRequestReview") {
                    Field.id
                    Field("body")
                    Field("state")
                    Field("createdAt")
                    Field("updatedAt")
                    authorGroup
                }
            }

            Group("commits", paging: .last(count: 1)) {
                Group("commit") {
                    Group("checkSuites", paging: smallPage) {
                        Group("checkRuns", paging: smallPage) {
                            Fragment(on: "CheckRun") {
                                Field.id
                                Field("name")
                                Field("conclusion")
                                Field("startedAt")
                                Field("completedAt")
                                Field("permalink")
                            }
                        }
                    }
                    Group("status") {
                        Group("contexts") {
                            Fragment(on: "StatusContext") {
                                Field.id
                                Field("context")
                                Field("description")
                                Field("state")
                                Field("targetUrl")
                                Field("createdAt")
                            }
                        }
                    }
                }
            }

            Group("reactions", paging: smallPage) {
                Fragment(on: "Reaction") {
                    Field.id
                    Field("content")
                    Field("createdAt")
                    Group("user") { userFragment }
                }
            }

            commentGroup(for: "IssueComment")
        }
    }

    // MARK: - Full PR list, for query-text cost only

    /// The widest element tree Trailer builds: used to measure text generation, not scanning.
    static var allOpenPrsFragment: Fragment {
        Fragment(on: "Repository") {
            Field.id
            Group("pullRequests", ("states", "[OPEN]"), paging: largePage) {
                Fragment(on: "PullRequest") {
                    Field.id
                    Field("bodyText")
                    Field("state")
                    Field("createdAt")
                    Field("updatedAt")
                    Field("number")
                    Field("title")
                    Field("url")
                    Group("milestone") { milestoneFragment }
                    authorGroup
                    Group("assignees", paging: smallPage) { userFragment }
                    Group("labels", paging: smallPage) { labelFragment }
                    Field("headRefOid")
                    Field("mergeable")
                    Field("additions")
                    Field("deletions")
                    Field("headRefName")
                    Field("baseRefName")
                    Field("isDraft")
                    Group("mergedBy") { Fragment(on: "User") { Field.id } }
                    Group("baseRepository") { nameWithOwnerField }
                    Group("headRepository") { nameWithOwnerField }
                    Group("closingIssuesReferences", paging: smallPage) { Field.id }
                }
            }
        }
    }

    // MARK: - Query construction

    /// A batched query over `count` repository ids, as `Query.batching` would build it, but with the
    /// batch kept whole so that it lines up with a single generated payload.
    static func issuesBatch(repoCount: Int, perNode: Query.PerNodeBlock?) -> Query {
        batch(name: "Open Issues", ids: Payloads.repoIds(count: repoCount), fragment: allOpenIssuesFragment, perNode: perNode)
    }

    static func accompanyingBatch(prCount: Int, perNode: Query.PerNodeBlock?) -> Query {
        batch(name: "PR Accompanying Items", ids: Payloads.prIds(count: prCount), fragment: accompanyingPrFragment, perNode: perNode)
    }

    /// The widest tree, built as a query so its text generation can be timed.
    static func prListQuery() -> Query {
        batch(name: "Open PRs", ids: Payloads.repoIds(count: 100), fragment: allOpenPrsFragment, perNode: nil)
    }

    private static func batch(name: String, ids: [String], fragment: Fragment, perNode: Query.PerNodeBlock?) -> Query {
        let template = Group("items") { fragment }
        let batchGroup = BatchGroup(name: "nodes", templateGroup: template, idList: ids)
        return Query(name: name, rootElement: batchGroup, checkRate: true, perNode: perNode)
    }
}
