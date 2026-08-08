import XCTest
@testable import Agent0Core

final class Agent0CoreTests: XCTestCase {
    func testAppendOnlyLedgerAndReplay() throws {
        let dir = try makeTempDir()
        let brain = Agent0Brain(directory: dir)

        let first = try brain.tick(observing: "if rain then wet")
        let firstLines = try lineCount(dir.appendingPathComponent("events.jsonl"))
        XCTAssertEqual(first.decision, .grow)
        XCTAssertEqual(first.newLaws.map(\.key), ["rain->wet"])
        XCTAssertEqual(Set(first.scaffolds.map(\.id)), Set(["ground-concept:rain", "ground-concept:wet", "verify-law:rain->wet"]))
        XCTAssertEqual(Set(first.scaffolds.map(\.status)), Set(["materialized"]))
        for scaffold in first.scaffolds {
            let artifact = try XCTUnwrap(scaffold.artifact)
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(artifact).path))
        }
        XCTAssertGreaterThan(firstLines, 0)

        let second = try Agent0Brain(directory: dir).tick(observing: "rain")
        let secondLines = try lineCount(dir.appendingPathComponent("events.jsonl"))
        XCTAssertGreaterThan(secondLines, firstLines)
        XCTAssertEqual(second.unmetPredictions, ["wet"])

        let state = try Agent0Brain(directory: dir).state()
        XCTAssertEqual(state.tick, 2)
        XCTAssertNotNil(state.laws["rain->wet"])
        XCTAssertEqual(state.concepts["rain"]?.seen, 2)
        XCTAssertEqual(state.scaffolds.count, 3)
        XCTAssertTrue(state.scaffolds.values.allSatisfy { $0.status == "materialized" && $0.artifact != nil })
    }

    func testScaffoldMaterializationSurvivesRestartAndPreservesArtifacts() throws {
        let dir = try makeTempDir()
        _ = try Agent0Brain(directory: dir).tick(observing: "if seed then branch")

        let restarted = Agent0Brain(directory: dir)
        let state = try restarted.state()
        let scaffold = try XCTUnwrap(state.scaffolds["verify-law:seed->branch"])
        XCTAssertEqual(scaffold.status, "materialized")
        let artifact = try XCTUnwrap(scaffold.artifact)
        let artifactURL = dir.appendingPathComponent(artifact)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))

        let marker = "\noperator_note: keep this good part\n"
        try marker.append(to: artifactURL)
        let beforeLines = try lineCount(dir.appendingPathComponent("events.jsonl"))
        let rematerialized = try restarted.materializeQueuedScaffolds()
        let afterLines = try lineCount(dir.appendingPathComponent("events.jsonl"))

        XCTAssertEqual(rematerialized, [])
        XCTAssertEqual(afterLines, beforeLines)
        XCTAssertTrue(try String(contentsOf: artifactURL, encoding: .utf8).contains(marker.trimmingCharacters(in: .newlines)))
    }

    func testRestartAfterEveryThoughtStillTunesPrediction() throws {
        let dir = try makeTempDir()
        _ = try Agent0Brain(directory: dir).tick(observing: "if spark then light")
        _ = try Agent0Brain(directory: dir).tick(observing: "spark")
        let third = try Agent0Brain(directory: dir).tick(observing: "light")

        XCTAssertEqual(third.decision, .tune)
        XCTAssertEqual(third.metPredictions, ["light"])

        let state = try Agent0Brain(directory: dir).state()
        XCTAssertEqual(state.tick, 3)
        XCTAssertEqual(state.laws["spark->light"]?.support, 2)
        XCTAssertTrue(state.concepts.keys.contains("spark"))
        XCTAssertTrue(state.concepts.keys.contains("light"))
    }

    func testCorruptLedgerFailsClosed() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("events.jsonl")
        try "{bad json}\n".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try Agent0Brain(directory: dir).state()) { error in
            guard case Agent0CoreError.corruptLedger = error else {
                return XCTFail("expected corrupt ledger, got \(error)")
            }
        }
    }

    func testBadRouteRedirectKeepsGoodParts() throws {
        let dir = try makeTempDir()
        _ = try Agent0Brain(directory: dir).tick(observing: "if rain then wet")
        _ = try Agent0Brain(directory: dir).tick(observing: "rain")
        let redirected = try Agent0Brain(directory: dir).tick(observing: "rain")

        XCTAssertEqual(redirected.redirectedRoutes.map(\.lawKey), ["rain->wet"])
        XCTAssertTrue(redirected.scaffolds.contains { $0.id == "repair-route:rain->wet" })

        let state = try Agent0Brain(directory: dir).state()
        XCTAssertNil(state.laws["rain->wet"])
        XCTAssertNotNil(state.redirectedRoutes["rain->wet"])
        XCTAssertNotNil(state.scaffolds["repair-route:rain->wet"])
        XCTAssertNotNil(state.concepts["rain"])
        XCTAssertNotNil(state.concepts["wet"])
        XCTAssertEqual(state.tick, 3)

        let afterRedirect = try Agent0Brain(directory: dir).tick(observing: "rain")
        XCTAssertEqual(afterRedirect.predicted, [])
        XCTAssertEqual(afterRedirect.unmetPredictions, [])
    }

    func testManualRedirectDoesNotRestartLedger() throws {
        let dir = try makeTempDir()
        _ = try Agent0Brain(directory: dir).tick(observing: "if spark then light")
        let redirect = try Agent0Brain(directory: dir).redirectRoute(source: "spark", target: "light", reason: "bad route")

        XCTAssertEqual(redirect.lawKey, "spark->light")

        let state = try Agent0Brain(directory: dir).state()
        XCTAssertEqual(state.tick, 2)
        XCTAssertNil(state.laws["spark->light"])
        XCTAssertNotNil(state.redirectedRoutes["spark->light"])
        XCTAssertNotNil(state.concepts["spark"])
        XCTAssertNotNil(state.concepts["light"])
    }

    func testQuestionWordsDoNotBecomeDurableConcepts() throws {
        let dir = try makeTempDir()
        let result = try Agent0Brain(directory: dir).tick(observing: "what")

        XCTAssertEqual(result.decision, .ignore)
        XCTAssertEqual(result.concepts, [])

        let state = try Agent0Brain(directory: dir).state()
        XCTAssertEqual(state.concepts.count, 0)
        XCTAssertEqual(state.tick, 1)
    }

    func testConceptSuppressionPreservesLedgerButRemovesActiveConcept() throws {
        let dir = try makeTempDir()
        _ = try Agent0Brain(directory: dir).tick(observing: "alpha")
        let beforeLines = try lineCount(dir.appendingPathComponent("events.jsonl"))
        let redirect = try Agent0Brain(directory: dir).suppressConcept("alpha", reason: "bad concept")
        let afterLines = try lineCount(dir.appendingPathComponent("events.jsonl"))

        XCTAssertEqual(redirect.concept, "alpha")
        XCTAssertGreaterThan(afterLines, beforeLines)

        let state = try Agent0Brain(directory: dir).state()
        XCTAssertNil(state.concepts["alpha"])
        XCTAssertNotNil(state.redirectedConcepts["alpha"])

        let next = try Agent0Brain(directory: dir).tick(observing: "alpha")
        XCTAssertEqual(next.decision, .ignore)
        XCTAssertEqual(next.concepts, [])
    }

    func testSuppressionCanCorrectPreviouslyGrownStopWord() throws {
        let dir = try makeTempDir()
        let ledger = CognitiveLedger(directory: dir)
        let now = Date(timeIntervalSince1970: 0)
        try ledger.append([
            CognitiveEvent(seq: 1, tick: 1, kind: .observation, subject: "michael", predicate: "said", object: "what", confidence: 1, evidence: [], note: "legacy bad concept", createdAt: now),
            CognitiveEvent(seq: 2, tick: 1, kind: .conceptGrown, subject: "what", predicate: "born-from", object: "observation", confidence: 0.5, evidence: [1], note: "legacy bad concept", createdAt: now),
            CognitiveEvent(seq: 3, tick: 1, kind: .tickCommitted, subject: "tick-1", predicate: "committed", object: nil, confidence: 0.5, evidence: [1, 2], note: "legacy bad concept", createdAt: now)
        ])

        let redirect = try Agent0Brain(directory: dir).suppressConcept("what", reason: "question word")
        XCTAssertEqual(redirect.concept, "what")

        let state = try Agent0Brain(directory: dir).state()
        XCTAssertNil(state.concepts["what"])
        XCTAssertNotNil(state.redirectedConcepts["what"])
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent0-core-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func lineCount(_ url: URL) throws -> Int {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: true).count
    }
}

private extension String {
    func append(to url: URL) throws {
        let data = Data(utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
