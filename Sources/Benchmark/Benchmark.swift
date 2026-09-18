import Foundation
import Synchronization
import TrailerJson
import TrailerQL

/// Baseline measurements for the paths that the optimisation work touches.
///
/// Every phase reports a fingerprint as well as a time. The fingerprints (node counts by type,
/// continuation-query counts, hashes of the generated query text) must not move when the internals
/// change, so they are the correctness check that goes alongside the numbers.
@main
enum Benchmark {
    private static let repoCount = 50
    private static let prCount = 100
    private static let scanIterations = 10
    private static let textIterations = 200

    static func main() async throws {
        print("!!! Run this with `swift run -c release Benchmark`, otherwise the numbers are meaningless")
        print()

        try await scanPhase(
            title: "Scan: open issues (real capture, amplified \(repoCount)x)",
            payload: Payloads.issues(repoCount: repoCount),
            query: { Schemas.issuesBatch(repoCount: repoCount, perNode: $0) }
        )

        try await scanPhase(
            title: "Scan: PR accompanying items (synthetic, \(prCount) PRs, 8 levels deep)",
            payload: Payloads.accompanyingItems(prCount: prCount),
            query: { Schemas.accompanyingBatch(prCount: prCount, perNode: $0) }
        )

        try textPhase()
        try constructionPhase()
    }

    private static let messagesDelivered = Atomic<Int>(0)

    /// The sink is `@LogActor` isolated, so installing it means hopping onto that actor.
    @LogActor
    private static func installLogSink(_ sink: ((String) -> Void)?) {
        TQL.debugLog = sink
    }

    // MARK: - Scanning

    private static func scanPhase(title: String, payload: Data, query: (Query.PerNodeBlock?) -> Query) async throws {
        print("### \(title)")
        print("Payload: \(bytes(payload.count)), \(scanIterations) iterations")

        // Parsing is TrailerJson's cost, not TrailerQL's, so time it separately and scan a tree
        // that is already built.
        let parse = try measure(iterations: scanIterations) {
            _ = try payload.asTypedJson()
        }
        guard let json = try payload.asTypedJson() else {
            throw Payloads.Failure.unexpectedCaptureShape
        }

        let collector = Collector()
        let scanQuery = query { output in
            collector.record(output)
        }

        // Warm up, and capture the fingerprint from a clean run.
        await collector.reset()
        var continuations = try await scanQuery.processResponse(from: json).count
        let fingerprint = await collector.fingerprint()

        let scan = try await measureAsync(iterations: scanIterations) {
            await collector.reset()
            continuations = try await scanQuery.processResponse(from: json).count
        }

        // What a sync actually pays: the scan, plus the text for every continuation it queued,
        // since each of those gets sent. Building that text eagerly or lazily moves cost between
        // the two phases, so only the total is comparable across changes.
        let endToEnd = try await measureAsync(iterations: scanIterations) {
            await collector.reset()
            for query in try await scanQuery.processResponse(from: json) {
                _ = query.queryText
            }
        }

        print("  JSON scan (TrailerJson):   \(ms(parse.mean)) ms mean, \(ms(parse.best)) ms best")
        print("  Node scan (TrailerQL):     \(ms(scan.mean)) ms mean, \(ms(scan.best)) ms best")
        let nodes = await collector.nodeCount
        print("  Scan + continuation text:  \(ms(endToEnd.mean)) ms mean, \(ms(endToEnd.best)) ms best")
        print("  Nodes:                     \(nodes) (\(perMs(nodes, scan.best)) nodes/ms at best), \(continuations) continuation queries")
        print("  Fingerprint:               \(fingerprint)")

        // The same scan with a sink installed, to price the logging path. The delivered count also
        // confirms the sink really is being reached, since a gate that never opened would look
        // identical to logging being cheap.
        messagesDelivered.store(0, ordering: .relaxed)
        await installLogSink { _ in
            messagesDelivered.add(1, ordering: .relaxed)
        }
        let logged = try await measureAsync(iterations: scanIterations) {
            await collector.reset()
            _ = try await scanQuery.processResponse(from: json).count
        }
        await installLogSink(nil)
        let delivered = messagesDelivered.load(ordering: .relaxed) / scanIterations
        print("  Node scan, logging on:     \(ms(logged.mean)) ms mean, \(ms(logged.best)) ms best (\(ratio(logged.best, scan.best))x)")
        print("  Log messages delivered:    \(delivered) per scan")

        // And with no sink, nothing should be delivered at all.
        messagesDelivered.store(0, ordering: .relaxed)
        _ = try await scanQuery.processResponse(from: json)
        print("  Delivered with no sink:    \(messagesDelivered.load(ordering: .relaxed)) (expected 0)")
        print()
    }

    // MARK: - Query text

    private static func textPhase() throws {
        print("### Query text generation (\(textIterations) iterations)")

        let issues = Schemas.issuesBatch(repoCount: repoCount, perNode: nil)
        let accompanying = Schemas.accompanyingBatch(prCount: prCount, perNode: nil)
        let prList = Schemas.prListQuery()

        for (label, query) in [("Open issues batch", issues), ("PR accompanying items", accompanying), ("Open PRs (widest tree)", prList)] {
            let text = query.queryText
            let time = try measure(iterations: textIterations) {
                _ = query.queryText
            }
            let cost = query.nodeCost
            let costTime = try measure(iterations: textIterations) {
                _ = query.nodeCost
            }
            // Fragment declarations are emitted in `Set` iteration order, which is seeded per
            // process, so the exact text can differ run to run. The canonical hash ignores
            // ordering, and `stable` reports whether repeated calls agree within one process.
            let stable = (0 ..< 8).allSatisfy { _ in query.queryText == text }
            print("  \(label)")
            print("    queryText: \(us(time.best)) µs/call, \(bytes(text.utf8.count)), hash \(hash(text)), canonical \(canonicalHash(text))")
            print("    stable within process: \(stable ? "yes" : "NO")")
            print("    nodeCost:  \(us(costTime.best)) µs/call, value \(cost)")
        }
        print()
    }

    // MARK: - Element tree construction

    private static func constructionPhase() throws {
        print("### Element tree construction (\(textIterations) iterations)")

        let time = try measure(iterations: textIterations) {
            _ = Schemas.allOpenPrsFragment
        }
        print("  Widest fragment tree: \(us(time.best)) µs/build, name \(Schemas.allOpenPrsFragment.name)")
        print()
    }

    // MARK: - Node collection

    /// Counts what the scan produced, so a refactor can be checked for having scanned the same tree.
    @Query.NodeActor
    private final class Collector {
        private(set) var nodeCount = 0
        private var typeCounts = [String: Int]()
        private var pageCompletions = 0

        func record(_ output: ParseOutput) {
            switch output {
            case let .node(node):
                nodeCount += 1
                typeCounts[node.elementType, default: 0] += 1
            case .queryPageComplete:
                pageCompletions += 1
            case .queryComplete:
                break
            }
        }

        func reset() {
            nodeCount = 0
            typeCounts.removeAll(keepingCapacity: true)
            pageCompletions = 0
        }

        func fingerprint() -> String {
            let types = typeCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            return "\(nodeCount) nodes, \(pageCompletions) page(s) [\(types)]"
        }
    }

    // MARK: - Timing

    /// Mean and best-of-N. The mean moves around with whatever else the machine is doing, so the
    /// minimum is the number to compare across runs.
    private struct Timing {
        let mean: Duration
        let best: Duration
    }

    private static func measure(iterations: Int, _ work: () throws -> Void) throws -> Timing {
        var total = Duration.zero
        var best = Duration.seconds(Int.max)
        for _ in 0 ..< iterations {
            let start = ContinuousClock.now
            try work()
            let taken = ContinuousClock.now - start
            total += taken
            best = min(best, taken)
        }
        return Timing(mean: total / iterations, best: best)
    }

    private static func measureAsync(iterations: Int, _ work: () async throws -> Void) async throws -> Timing {
        var total = Duration.zero
        var best = Duration.seconds(Int.max)
        for _ in 0 ..< iterations {
            let start = ContinuousClock.now
            try await work()
            let taken = ContinuousClock.now - start
            total += taken
            best = min(best, taken)
        }
        return Timing(mean: total / iterations, best: best)
    }

    // MARK: - Formatting

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func ms(_ duration: Duration) -> String {
        String(format: "%.3f", seconds(duration) * 1000)
    }

    private static func us(_ duration: Duration) -> String {
        String(format: "%.2f", seconds(duration) * 1_000_000)
    }

    private static func perMs(_ count: Int, _ duration: Duration) -> String {
        String(format: "%.1f", Double(count) / (seconds(duration) * 1000))
    }

    private static func ratio(_ lhs: Duration, _ rhs: Duration) -> String {
        String(format: "%.2f", seconds(lhs) / seconds(rhs))
    }

    private static func bytes(_ count: Int) -> String {
        count < 1024 ? "\(count) B" : String(format: "%.1f KB", Double(count) / 1024)
    }

    /// FNV-1a, so query text can be compared across runs without printing kilobytes of it.
    private static func hash(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// A hash of the byte histogram: sensitive to content, blind to the order the fragment
    /// declarations happen to come out in. Comparable across runs even while ordering is unstable.
    private static func canonicalHash(_ text: String) -> String {
        var counts = [Int](repeating: 0, count: 256)
        for byte in text.utf8 {
            counts[Int(byte)] += 1
        }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for count in counts {
            for shift in stride(from: 0, to: 64, by: 8) {
                hash ^= UInt64(UInt8(truncatingIfNeeded: count >> shift))
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return String(hash, radix: 16)
    }
}
