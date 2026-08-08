import CryptoKit
import Foundation

public enum CognitiveDecision: String, Codable, Equatable {
    case ignore
    case tune
    case grow
}

public enum CognitiveEventKind: String, Codable, Equatable {
    case observation
    case conceptSeen
    case conceptGrown
    case prediction
    case decision
    case lawPromoted
    case lawTuned
    case verification
    case tension
    case conceptRedirected
    case routeRedirected
    case scaffoldQueued
    case scaffoldMaterialized
    case tickCommitted
}

public struct CognitiveEvent: Codable, Equatable {
    public let seq: Int
    public let tick: Int
    public let kind: CognitiveEventKind
    public let subject: String
    public let predicate: String
    public let object: String?
    public let confidence: Double
    public let evidence: [Int]
    public let note: String
    public let createdAt: Date
}

public struct ConceptRecord: Codable, Equatable {
    public var name: String
    public var seen: Int
    public var firstSeq: Int
    public var lastSeq: Int
}

public struct CausalLaw: Codable, Equatable {
    public var source: String
    public var relation: String
    public var target: String
    public var support: Int
    public var confidence: Double
    public var lastSeq: Int

    public var key: String { Self.key(source, target) }

    public static func key(_ source: String, _ target: String) -> String {
        "\(source)->\(target)"
    }
}

public struct RouteRedirect: Codable, Equatable {
    public var lawKey: String
    public var reason: String
    public var replacement: String?
    public var createdSeq: Int
}

public struct ConceptRedirect: Codable, Equatable {
    public var concept: String
    public var reason: String
    public var replacement: String?
    public var createdSeq: Int
}

public struct ScaffoldRecord: Codable, Equatable {
    public var id: String
    public var kind: String
    public var target: String
    public var reason: String
    public var status: String
    public var evidence: [Int]
    public var createdSeq: Int
    public var artifact: String?
}

public struct Agent0State: Codable, Equatable {
    public var tick: Int
    public var lastSequence: Int
    public var ledgerHash: String
    public var concepts: [String: ConceptRecord]
    public var laws: [String: CausalLaw]
    public var redirectedConcepts: [String: ConceptRedirect]
    public var redirectedRoutes: [String: RouteRedirect]
    public var routeFailures: [String: Int]
    public var scaffolds: [String: ScaffoldRecord]
    public var lastConcepts: [String]
    public var unresolvedTensions: [String]
}

public struct ThoughtResult: Codable, Equatable {
    public let tick: Int
    public let decision: CognitiveDecision
    public let observation: String
    public let concepts: [String]
    public let predicted: [String]
    public let metPredictions: [String]
    public let unmetPredictions: [String]
    public let newConcepts: [String]
    public let newLaws: [CausalLaw]
    public let tunedLaws: [CausalLaw]
    public let redirectedRoutes: [RouteRedirect]
    public let scaffolds: [ScaffoldRecord]
    public let predictionError: Double
    public let confidence: Double
    public let events: [CognitiveEvent]
    public let reply: String
    public let ledgerURL: URL
}

public enum Agent0CoreError: LocalizedError, Equatable {
    case corruptLedger(URL, line: Int, reason: String)
    case emptyObservation

    public var errorDescription: String? {
        switch self {
        case let .corruptLedger(url, line, reason):
            return "corrupt ledger at \(url.path):\(line): \(reason)"
        case .emptyObservation:
            return "empty observation"
        }
    }
}

public final class CognitiveLedger {
    public let url: URL

    public init(directory: URL, filename: String = "events.jsonl") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent(filename)
    }

    public func read() throws -> [CognitiveEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let raw = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [CognitiveEvent] = []
        for (idx, line) in raw.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            do {
                let data = Data(line.utf8)
                events.append(try decoder.decode(CognitiveEvent.self, from: data))
            } catch {
                throw Agent0CoreError.corruptLedger(url, line: idx + 1, reason: error.localizedDescription)
            }
        }
        return events
    }

    public func append(_ events: [CognitiveEvent]) throws {
        guard !events.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for event in events {
            var data = try encoder.encode(event)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
        try handle.synchronize()
    }
}

public final class Agent0Brain {
    private let ledger: CognitiveLedger
    private let directory: URL
    private let clock: () -> Date

    public init(directory: URL, clock: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.ledger = CognitiveLedger(directory: directory)
        self.clock = clock
    }

    public func state() throws -> Agent0State {
        try Agent0Projector.replay(ledger.read())
    }

    @discardableResult
    public func suppressConcept(_ rawConcept: String, reason: String = "low-signal concept") throws -> ConceptRedirect {
        guard let concept = Self.normalizedConceptName(rawConcept) else { throw Agent0CoreError.emptyObservation }
        let state = try Agent0Projector.replay(ledger.read())
        let tick = state.tick + 1
        var nextSeq = state.lastSequence + 1
        let redirect = ConceptRedirect(concept: concept, reason: reason, replacement: nil, createdSeq: nextSeq)
        let now = clock()
        let event = CognitiveEvent(
            seq: nextSeq,
            tick: tick,
            kind: .conceptRedirected,
            subject: concept,
            predicate: "suppress-concept",
            object: nil,
            confidence: 1.0,
            evidence: [],
            note: reason,
            createdAt: now
        )
        nextSeq += 1
        let commit = CognitiveEvent(
            seq: nextSeq,
            tick: tick,
            kind: .tickCommitted,
            subject: "tick-\(tick)",
            predicate: "committed",
            object: nil,
            confidence: 1.0,
            evidence: [event.seq],
            note: "concept redirect",
            createdAt: now
        )
        try ledger.append([event, commit])
        return redirect
    }

    @discardableResult
    public func redirectRoute(source rawSource: String, target rawTarget: String, reason: String = "manual redirect") throws -> RouteRedirect {
        guard let source = Self.normalConcept(rawSource), let target = Self.normalConcept(rawTarget) else {
            throw Agent0CoreError.emptyObservation
        }
        let state = try Agent0Projector.replay(ledger.read())
        let tick = state.tick + 1
        var nextSeq = state.lastSequence + 1
        let key = CausalLaw.key(source, target)
        let redirect = RouteRedirect(lawKey: key, reason: reason, replacement: nil, createdSeq: nextSeq)
        let now = clock()
        let event = CognitiveEvent(
            seq: nextSeq,
            tick: tick,
            kind: .routeRedirected,
            subject: key,
            predicate: "manual-redirect",
            object: nil,
            confidence: 1.0,
            evidence: [],
            note: reason,
            createdAt: now
        )
        nextSeq += 1
        let commit = CognitiveEvent(
            seq: nextSeq,
            tick: tick,
            kind: .tickCommitted,
            subject: "tick-\(tick)",
            predicate: "committed",
            object: nil,
            confidence: 1.0,
            evidence: [event.seq],
            note: "manual redirect",
            createdAt: now
        )
        try ledger.append([event, commit])
        return redirect
    }

    @discardableResult
    public func materializeQueuedScaffolds() throws -> [ScaffoldRecord] {
        let state = try Agent0Projector.replay(ledger.read())
        let queued = state.scaffolds.values
            .filter { $0.status == "queued" }
            .sorted { $0.id < $1.id }
        guard !queued.isEmpty else { return [] }

        let scaffoldDir = directory.appendingPathComponent("scaffolds", isDirectory: true)
        try FileManager.default.createDirectory(at: scaffoldDir, withIntermediateDirectories: true)

        var nextSeq = state.lastSequence + 1
        var events: [CognitiveEvent] = []
        var materialized: [ScaffoldRecord] = []
        for scaffold in queued {
            let artifact = "scaffolds/\(Self.safeArtifactName(scaffold.id)).md"
            let artifactURL = directory.appendingPathComponent(artifact, isDirectory: false)
            if !FileManager.default.fileExists(atPath: artifactURL.path) {
                try Self.scaffoldDocument(for: scaffold, artifact: artifact)
                    .write(to: artifactURL, atomically: true, encoding: .utf8)
            }

            let seq = nextSeq
            nextSeq += 1
            events.append(CognitiveEvent(
                seq: seq,
                tick: state.tick,
                kind: .scaffoldMaterialized,
                subject: scaffold.id,
                predicate: scaffold.kind,
                object: artifact,
                confidence: 1.0,
                evidence: Self.unique(scaffold.evidence + [scaffold.createdSeq]),
                note: scaffold.reason,
                createdAt: clock()
            ))

            var updated = scaffold
            updated.status = "materialized"
            updated.artifact = artifact
            materialized.append(updated)
        }

        try ledger.append(events)
        return materialized
    }

    @discardableResult
    public func tick(observing rawText: String, speaker: String = "user") throws -> ThoughtResult {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Agent0CoreError.emptyObservation }

        let previousEvents = try ledger.read()
        let state = try Agent0Projector.replay(previousEvents)
        let tick = state.tick + 1
        var nextSeq = state.lastSequence + 1
        var emitted: [CognitiveEvent] = []

        @discardableResult
        func emit(_ kind: CognitiveEventKind, _ subject: String, _ predicate: String, _ object: String?, _ confidence: Double, _ evidence: [Int], _ note: String) -> Int {
            let seq = nextSeq
            emitted.append(CognitiveEvent(
                seq: seq,
                tick: tick,
                kind: kind,
                subject: subject,
                predicate: predicate,
                object: object,
                confidence: max(0, min(1, confidence)),
                evidence: evidence,
                note: note,
                createdAt: clock()
            ))
            nextSeq += 1
            return seq
        }

        let rawConcepts = Self.tokenize(text)
        let concepts = rawConcepts.filter { state.redirectedConcepts[$0] == nil }
        let known = concepts.filter { state.concepts[$0] != nil }
        let newConcepts = concepts.filter { state.concepts[$0] == nil }
        let candidates = Self.extractLaws(from: text, concepts: concepts)
        let predictionCandidates = Self.predictions(for: concepts, lastConcepts: state.lastConcepts, laws: Array(state.laws.values))
        let predicted = Self.unique(predictionCandidates.map(\.target))
        let met = predicted.filter { concepts.contains($0) }
        let unmet = predicted.filter { !concepts.contains($0) }

        let unknownRatio = concepts.isEmpty ? 0 : Double(newConcepts.count) / Double(concepts.count)
        let unmetRatio = predicted.isEmpty ? 0 : Double(unmet.count) / Double(predicted.count)
        let lawBonus = candidates.isEmpty ? 0.0 : 0.35
        let error = min(1.0, unknownRatio * 0.55 + unmetRatio * 0.35 + lawBonus)
        let decision: CognitiveDecision
        if concepts.isEmpty {
            decision = .ignore
        } else if !newConcepts.isEmpty || !candidates.isEmpty || !unmet.isEmpty {
            decision = .grow
        } else if !known.isEmpty || !met.isEmpty {
            decision = .tune
        } else {
            decision = .ignore
        }
        let confidence = 1.0 - min(0.95, error * 0.75)

        emit(.observation, speaker, "said", text, 1.0, [], "before=\(state.ledgerHash)")
        let observationSeq = emitted.last?.seq ?? state.lastSequence

        if !predicted.isEmpty {
            emit(.prediction, "active-context", "expects", predicted.joined(separator: ","), confidence, [observationSeq], "met=\(met.joined(separator: ","));unmet=\(unmet.joined(separator: ","))")
        }

        var scaffolds: [ScaffoldRecord] = []
        func queueScaffold(id: String, kind: String, target: String, reason: String, evidence: [Int], confidence: Double) {
            guard state.scaffolds[id] == nil, !scaffolds.contains(where: { $0.id == id }) else { return }
            let scaffold = ScaffoldRecord(
                id: id,
                kind: kind,
                target: target,
                reason: reason,
                status: "queued",
                evidence: evidence,
                createdSeq: nextSeq,
                artifact: nil
            )
            scaffolds.append(scaffold)
            emit(.scaffoldQueued, id, kind, target, confidence, evidence, reason)
        }

        for concept in concepts {
            if state.concepts[concept] == nil {
                let conceptSeq = emit(.conceptGrown, concept, "born-from", "observation", confidence, [observationSeq], "new concept")
                queueScaffold(
                    id: "ground-concept:\(concept)",
                    kind: "ground-concept",
                    target: concept,
                    reason: "collect examples and counterexamples before treating \(concept) as stable",
                    evidence: [conceptSeq],
                    confidence: confidence
                )
            } else {
                emit(.conceptSeen, concept, "reinforced-by", "observation", confidence, [observationSeq], "seen again")
            }
        }

        var promoted: [CausalLaw] = []
        var tuned: [CausalLaw] = []
        var tunedKeys = Set<String>()
        for candidate in candidates {
            let key = CausalLaw.key(candidate.source, candidate.target)
            var law = state.laws[key] ?? CausalLaw(source: candidate.source, relation: candidate.relation, target: candidate.target, support: 0, confidence: 0.45, lastSeq: 0)
            law.support += 1
            law.confidence = min(0.99, law.confidence + 0.12)
            law.lastSeq = nextSeq
            if state.laws[key] == nil {
                promoted.append(law)
                let lawSeq = emit(.lawPromoted, law.source, law.relation, law.target, law.confidence, [observationSeq], "promoted from explicit observation")
                queueScaffold(
                    id: "verify-law:\(law.key)",
                    kind: "verify-law",
                    target: law.key,
                    reason: "seek a confirming and disconfirming observation for \(law.key)",
                    evidence: [lawSeq],
                    confidence: law.confidence
                )
            } else {
                tuned.append(law)
                tunedKeys.insert(key)
                emit(.lawTuned, law.source, law.relation, law.target, law.confidence, [observationSeq], "reinforced by repeated evidence")
            }
        }

        for candidate in predictionCandidates where concepts.contains(candidate.target) {
            guard !tunedKeys.contains(candidate.key) else { continue }
            var law = candidate.law
            law.support += 1
            law.confidence = min(0.99, law.confidence + 0.08)
            law.lastSeq = nextSeq
            tuned.append(law)
            tunedKeys.insert(candidate.key)
            emit(.lawTuned, law.source, law.relation, law.target, law.confidence, [observationSeq], "prediction met")
        }

        var redirected: [RouteRedirect] = []
        var redirectedKeys = Set<String>()
        for candidate in predictionCandidates where !concepts.contains(candidate.target) {
            emit(.tension, candidate.key, "unmet-prediction", candidate.target, max(0.05, error), [observationSeq], "expected \(candidate.target) from \(candidate.source)")
            let failures = state.routeFailures[candidate.key, default: 0] + 1
            if failures >= 2 && !redirectedKeys.contains(candidate.key) {
                let redirect = RouteRedirect(
                    lawKey: candidate.key,
                    reason: "unmet prediction \(failures)x: expected \(candidate.target) when \(candidate.source) was active",
                    replacement: nil,
                    createdSeq: nextSeq
                )
                redirected.append(redirect)
                redirectedKeys.insert(candidate.key)
                let redirectSeq = emit(.routeRedirected, candidate.key, "auto-redirect", nil, max(0.1, error), [observationSeq], redirect.reason)
                queueScaffold(
                    id: "repair-route:\(candidate.key)",
                    kind: "repair-route",
                    target: candidate.key,
                    reason: "find the missing condition that made \(candidate.key) fail",
                    evidence: [redirectSeq],
                    confidence: max(0.1, error)
                )
            }
        }

        emit(.decision, decision.rawValue, "prediction-error", String(format: "%.3f", error), confidence, [observationSeq], "ignore-tune-grow")
        emit(.verification, decision.rawValue, "confidence", String(format: "%.3f", confidence), confidence, emitted.map(\.seq), "local replay verified")
        emit(.tickCommitted, "tick-\(tick)", "committed", nil, confidence, emitted.map(\.seq), "events=\(emitted.count + 1)")

        try ledger.append(emitted)
        let materializedScaffolds = try materializeQueuedScaffolds()
        let materializedByID = Dictionary(uniqueKeysWithValues: materializedScaffolds.map { ($0.id, $0) })
        let returnedScaffolds = scaffolds.map { materializedByID[$0.id] ?? $0 }

        let reply = Self.reply(
            decision: decision,
            newConcepts: newConcepts,
            promoted: promoted,
            tuned: tuned,
            predicted: predicted,
            met: met,
            unmet: unmet,
            error: error,
            confidence: confidence
        )

        return ThoughtResult(
            tick: tick,
            decision: decision,
            observation: text,
            concepts: concepts,
            predicted: predicted,
            metPredictions: met,
            unmetPredictions: unmet,
            newConcepts: newConcepts,
            newLaws: promoted,
            tunedLaws: tuned,
            redirectedRoutes: redirected,
            scaffolds: returnedScaffolds,
            predictionError: error,
            confidence: confidence,
            events: emitted,
            reply: reply,
            ledgerURL: ledger.url
        )
    }

    public static func tokenize(_ text: String) -> [String] {
        let stop: Set<String> = [
            "the", "a", "an", "and", "or", "but", "to", "of", "is", "it", "i", "you", "me", "my", "that",
            "this", "in", "on", "for", "with", "are", "was", "be", "do", "so", "as", "at", "we", "your",
            "from", "into", "by", "then", "if", "when",
            "what", "why", "who", "where", "which", "whats", "what's",
            "grow", "tune", "ignore", "concept", "concepts", "error", "route", "routes"
        ]
        var seen = Set<String>()
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 && !stop.contains($0) }
            .filter { seen.insert($0).inserted }
    }

    private static func normalConcept(_ raw: String) -> String? {
        tokenize(raw).first
    }

    private static func normalizedConceptName(_ raw: String) -> String? {
        raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count > 1 }
    }

    private struct PredictionCandidate {
        let law: CausalLaw
        var key: String { law.key }
        var source: String { law.source }
        var target: String { law.target }
    }

    private static func predictions(for concepts: [String], lastConcepts: [String], laws: [CausalLaw]) -> [PredictionCandidate] {
        let active = Set(concepts + lastConcepts)
        var out: [PredictionCandidate] = []
        for law in laws where active.contains(law.source) {
            if !out.contains(where: { $0.target == law.target }) {
                out.append(PredictionCandidate(law: law))
            }
        }
        return out
    }

    private static func extractLaws(from text: String, concepts: [String]) -> [(source: String, relation: String, target: String)] {
        let raw = text.lowercased()
        var out: [(source: String, relation: String, target: String)] = []

        if raw.contains("->") {
            let parts = raw.components(separatedBy: "->")
            if parts.count >= 2,
               let source = tokenize(parts[0]).last,
               let target = tokenize(parts[1]).first,
               source != target {
                out.append((source: source, relation: "predicts", target: target))
            }
        }

        let words = raw.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if let ifIndex = words.firstIndex(of: "if"),
           let thenIndex = words.firstIndex(of: "then"),
           ifIndex < thenIndex,
           let source = tokenize(words[(ifIndex + 1)..<thenIndex].joined(separator: " ")).last,
           let target = tokenize(words[(thenIndex + 1)..<words.count].joined(separator: " ")).first,
           source != target {
            out.append((source: source, relation: "predicts", target: target))
        }

        let relationWords = ["causes", "cause", "makes", "make", "creates", "create", "precedes", "predicts"]
        for relation in relationWords {
            guard let idx = words.firstIndex(of: relation), idx > 0, idx + 1 < words.count else { continue }
            let left = tokenize(words[..<idx].joined(separator: " ")).last
            let right = tokenize(words[(idx + 1)..<words.count].joined(separator: " ")).first
            if let source = left, let target = right, source != target {
                out.append((source: source, relation: "predicts", target: target))
            }
        }

        if out.isEmpty, concepts.count >= 2, raw.contains("means") {
            out.append((source: concepts[0], relation: "predicts", target: concepts[1]))
        }

        return unique(out, by: { CausalLaw.key($0.source, $0.target) })
    }

    private static func reply(
        decision: CognitiveDecision,
        newConcepts: [String],
        promoted: [CausalLaw],
        tuned: [CausalLaw],
        predicted: [String],
        met: [String],
        unmet: [String],
        error: Double,
        confidence: Double
    ) -> String {
        let err = String(format: "%.2f", error)
        let conf = String(format: "%.2f", confidence)
        switch decision {
        case .grow:
            var parts: [String] = []
            if !newConcepts.isEmpty { parts.append("concepts \(newConcepts.prefix(4).joined(separator: ", "))") }
            if !promoted.isEmpty { parts.append("laws \(promoted.map { "\($0.source)->\($0.target)" }.joined(separator: ", "))") }
            if !unmet.isEmpty { parts.append("tension expected \(unmet.joined(separator: ", "))") }
            return "GROW \(parts.isEmpty ? "new structure" : parts.joined(separator: "; ")). surprise \(err), confidence \(conf)."
        case .tune:
            var parts: [String] = []
            if !tuned.isEmpty { parts.append("laws \(tuned.map { "\($0.source)->\($0.target)" }.joined(separator: ", "))") }
            if !met.isEmpty { parts.append("met prediction \(met.joined(separator: ", "))") }
            if parts.isEmpty, !predicted.isEmpty { parts.append("expected \(predicted.joined(separator: ", "))") }
            return "TUNE \(parts.isEmpty ? "existing structure" : parts.joined(separator: "; ")). surprise \(err), confidence \(conf)."
        case .ignore:
            return "IGNORE no durable change needed. surprise \(err), confidence \(conf)."
        }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func safeArtifactName(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "scaffold" : collapsed
    }

    private static func scaffoldDocument(for scaffold: ScaffoldRecord, artifact: String) -> String {
        """
        # Agent0 Scaffold

        id: \(scaffold.id)
        kind: \(scaffold.kind)
        target: \(scaffold.target)
        status: materialized
        artifact: \(artifact)
        created_seq: \(scaffold.createdSeq)
        evidence: \(scaffold.evidence.map(String.init).joined(separator: ","))

        reason:
        \(scaffold.reason)

        next:
        - collect direct observations for the target
        - collect counterexamples before promotion
        - redirect this scaffold instead of deleting it if the route proves bad
        """
    }

    private static func unique<T>(_ values: [T], by key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return values.filter { seen.insert(key($0)).inserted }
    }
}

enum Agent0Projector {
    static func replay(_ events: [CognitiveEvent]) throws -> Agent0State {
        var concepts: [String: ConceptRecord] = [:]
        var laws: [String: CausalLaw] = [:]
        var redirectedConcepts: [String: ConceptRedirect] = [:]
        var redirectedRoutes: [String: RouteRedirect] = [:]
        var routeFailures: [String: Int] = [:]
        var scaffolds: [String: ScaffoldRecord] = [:]
        var tickConcepts: [Int: [String]] = [:]
        var tensions: [String] = []

        for event in events.sorted(by: { $0.seq < $1.seq }) {
            switch event.kind {
            case .conceptGrown, .conceptSeen:
                guard redirectedConcepts[event.subject] == nil else { continue }
                var record = concepts[event.subject] ?? ConceptRecord(name: event.subject, seen: 0, firstSeq: event.seq, lastSeq: event.seq)
                record.seen += 1
                record.lastSeq = event.seq
                concepts[event.subject] = record
                tickConcepts[event.tick, default: []].append(event.subject)
            case .conceptRedirected:
                redirectedConcepts[event.subject] = ConceptRedirect(
                    concept: event.subject,
                    reason: event.note,
                    replacement: event.object,
                    createdSeq: event.seq
                )
                concepts[event.subject] = nil
            case .lawPromoted, .lawTuned:
                guard let target = event.object else { continue }
                let key = CausalLaw.key(event.subject, target)
                var law = laws[key] ?? CausalLaw(source: event.subject, relation: event.predicate, target: target, support: 0, confidence: event.confidence, lastSeq: event.seq)
                law.support += 1
                law.confidence = max(law.confidence, event.confidence)
                law.lastSeq = event.seq
                laws[key] = law
                redirectedRoutes[key] = nil
                routeFailures[key] = 0
            case .tension:
                let key = event.subject
                tensions.append(key)
                if event.predicate == "unmet-prediction" {
                    routeFailures[key, default: 0] += 1
                }
            case .routeRedirected:
                redirectedRoutes[event.subject] = RouteRedirect(
                    lawKey: event.subject,
                    reason: event.note,
                    replacement: event.object,
                    createdSeq: event.seq
                )
                laws[event.subject] = nil
            case .scaffoldQueued:
                guard let target = event.object else { continue }
                scaffolds[event.subject] = ScaffoldRecord(
                    id: event.subject,
                    kind: event.predicate,
                    target: target,
                    reason: event.note,
                    status: "queued",
                    evidence: event.evidence,
                    createdSeq: event.seq,
                    artifact: nil
                )
            case .scaffoldMaterialized:
                var scaffold = scaffolds[event.subject] ?? ScaffoldRecord(
                    id: event.subject,
                    kind: event.predicate,
                    target: event.subject,
                    reason: event.note,
                    status: "queued",
                    evidence: event.evidence,
                    createdSeq: event.seq,
                    artifact: nil
                )
                scaffold.status = "materialized"
                scaffold.artifact = event.object
                scaffold.evidence = uniqueInts(scaffold.evidence + event.evidence)
                scaffolds[event.subject] = scaffold
            default:
                break
            }
        }

        let lastTick = events.map(\.tick).max() ?? 0
        return Agent0State(
            tick: lastTick,
            lastSequence: events.map(\.seq).max() ?? 0,
            ledgerHash: hash(events),
            concepts: concepts,
            laws: laws,
            redirectedConcepts: redirectedConcepts,
            redirectedRoutes: redirectedRoutes,
            routeFailures: routeFailures,
            scaffolds: scaffolds,
            lastConcepts: tickConcepts[lastTick] ?? [],
            unresolvedTensions: Array(tensions.suffix(32))
        )
    }

    private static func hash(_ events: [CognitiveEvent]) -> String {
        var hasher = SHA256()
        for event in events.sorted(by: { $0.seq < $1.seq }) {
            let row = "\(event.seq)|\(event.tick)|\(event.kind.rawValue)|\(event.subject)|\(event.predicate)|\(event.object ?? "")|\(String(format: "%.5f", event.confidence))\n"
            hasher.update(data: Data(row.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func uniqueInts(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }
}
