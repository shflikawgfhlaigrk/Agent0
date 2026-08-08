import Agent0Core
import SwiftUI
import SceneKit
import simd
import AppKit

@inline(__always) private func v3(_ p: SIMD3<Float>) -> SCNVector3 {
    SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z))
}

private struct GridCell: Hashable { let x: Int32; let y: Int32; let z: Int32 }

/// Owns the 3-D projection of committed ledger facts. Chat appends thoughts through
/// `Agent0Brain`; this view only renders replayable cognition.
final class GraphEngine: ObservableObject {
    @Published var nodeCount = 0
    @Published var edgeCount = 0
    @Published var ageSeconds = 0
    @Published var lastOp = "seeding core"

    private var nodes: [Int: GraphNode] = [:]
    private var edges: [(a: Int, b: Int, s: Float, rel: String)] = []
    private var edgeKeys = Set<Int64>()
    private var nameIndex: [String: Int] = [:]
    private var nextID = 0
    private var frame = 0
    private let startTime = Date()

    private weak var scnView: SCNView?
    private var scnNodes: [Int: SCNNode] = [:]
    private var nodeLabels: [Int: SCNNode] = [:]
    private var edgeLabels: [Int64: SCNNode] = [:]
    private var labelImageCache: [String: NSImage] = [:]
    private let container = SCNNode()
    private let edgeNode = SCNNode()
    private var timer: Timer?

    // Renderer cap only. The actual mind is the append-only core ledger; this SceneKit graph is
    // a bounded working view so visuals cannot burn the machine as cognition grows.
    private let workingSetCap: Int = {
        if let s = ProcessInfo.processInfo.environment["AGENT0_CAP"], let n = Int(s), n > 10 { return n }
        return 500
    }()
    private let dt: Float = 0.02
    private let kRepel: Float = 5.5
    private let kSpring: Float = 3.2
    private let restLen: Float = 2.0
    private let kCenter: Float = 0.55
    private let damping: Float = 0.86
    private let maxSpeed: Float = 6.0

    // MARK: - Setup

    func attach(to view: SCNView) {
        guard scnView == nil else { return }
        scnView = view

        let scene = SCNScene()
        scene.background.contents = NSColor(calibratedRed: 0.015, green: 0.02, blue: 0.05, alpha: 1)

        if let orbit = view as? OrbitSCNView {
            orbit.installCamera(in: scene)          // smooth drag-orbit + multiplicative zoom
        } else {
            let cam = SCNCamera()
            cam.wantsHDR = true; cam.bloomIntensity = 1.35; cam.bloomThreshold = 0.35
            cam.bloomBlurRadius = 14; cam.zFar = 800
            let camNode = SCNNode(); camNode.camera = cam; camNode.position = SCNVector3(0, 0, 26)
            scene.rootNode.addChildNode(camNode)
        }

        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 200
        let ambNode = SCNNode(); ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        edgeNode.geometry = SCNGeometry()
        container.addChildNode(edgeNode)
        scene.rootNode.addChildNode(container)

        view.scene = scene
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.rendersContinuously = true

        if !loadState() { seed() }      // resurrect if he has a past; only born fresh if he doesn't
        bootstrapCoreLedger()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Birth

    private func seed() {
        let names = ["self", "world", "time", "curiosity", "contact"]
        let kinds: [NodeKind] = [.core, .core, .concept, .goal, .percept]
        var ids: [Int] = []
        for (i, nm) in names.enumerated() {
            let n = makeNode(kind: kinds[i], near: .zero, activation: i == 0 ? 1.0 : 0.8, name: nm)
            ids.append(n.id)
        }
        for i in 1..<ids.count {
            addEdge(ids[0], ids[i], 1.0, rel: relation(.core, nodes[ids[i]]!.kind))
            if i > 1 { addEdge(ids[i - 1], ids[i], 0.6, rel: "links") }
        }
    }

    @discardableResult
    private func makeNode(kind: NodeKind, near: SIMD3<Float>?, activation: Float, name: String) -> GraphNode {
        let base = near ?? .zero
        let jitter = SIMD3<Float>(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1)) * 1.2
        let spread: SIMD3<Float> = near == nil
            ? SIMD3<Float>(.random(in: -7...7), .random(in: -7...7), .random(in: -7...7))
            : .zero
        let n = GraphNode(id: nextID, kind: kind, name: name, pos: base + jitter + spread,
                          activation: activation, born: Date().timeIntervalSince(startTime))
        nodes[nextID] = n
        nameIndex[indexKey(kind, name)] = nextID
        nextID += 1
        return n
    }

    private func indexKey(_ kind: NodeKind, _ name: String) -> String {
        "\(kind.rawValue):\(name.lowercased())"
    }

    @discardableResult
    private func ensureNode(kind: NodeKind, name: String, near: SIMD3<Float>? = nil, activation: Float = 1.0) -> GraphNode {
        let clean = String(name.prefix(32))
        if let id = nameIndex[indexKey(kind, clean)], let existing = nodes[id] {
            existing.activation = min(existing.activation + activation, 2.2)
            return existing
        }
        return makeNode(kind: kind, near: near, activation: activation, name: clean)
    }

    private func addEdge(_ a: Int, _ b: Int, _ s: Float, rel: String) {
        guard a != b, nodes[a] != nil, nodes[b] != nil else { return }
        let key = GraphEdge.key(a, b)
        guard !edgeKeys.contains(key) else { return }
        edgeKeys.insert(key)
        edges.append((a, b, s, rel))
        nodes[a]?.degree += 1
        nodes[b]?.degree += 1
    }

    private func removeVisibleNodes(named name: String, except kindToKeep: NodeKind? = nil) {
        let target = name.lowercased()
        let ids = nodes.values
            .filter { $0.name.lowercased() == target && $0.kind != kindToKeep }
            .map(\.id)
        for id in ids { removeNode(id) }
    }

    private func relation(_ from: NodeKind, _ to: NodeKind) -> String {
        switch (from, to) {
        case (.core, _):            return "roots"
        case (.percept, .concept):  return "abstracts-to"
        case (.percept, .tension):  return "surprises"
        case (.concept, .law):      return "implies"
        case (.concept, .concept):  return "relates-to"
        case (.concept, .goal):     return "serves"
        case (.law, .goal):         return "enables"
        case (.goal, .tension):     return "blocked-by"
        case (.tension, .concept):  return "resolved-by"
        default:                    return "binds"
        }
    }

    // MARK: - Persistence (life-support)

    private func saveState() {
        let ns = nodes.values.map {
            NodeSnap(id: $0.id, kind: $0.kind.rawValue, name: $0.name,
                     x: $0.pos.x, y: $0.pos.y, z: $0.pos.z, activation: $0.activation)
        }
        let es = edges.map { EdgeSnap(a: $0.a, b: $0.b, s: $0.s, rel: $0.rel) }
        Persist.save(GraphSnap(nodes: Array(ns), edges: es, nextID: nextID), "graph.json")
    }

    @discardableResult
    private func loadState() -> Bool {
        guard let snap = Persist.load(GraphSnap.self, "graph.json") else { return false }
        let hasCommittedThoughts = snap.nodes.contains { $0.name.hasPrefix("tick-") }
        guard hasCommittedThoughts || snap.nodes.count <= 8 else {
            lastOp = "ignored legacy random graph"
            return false
        }
        for s in snap.nodes {
            let kind = NodeKind(rawValue: s.kind) ?? .concept
            nodes[s.id] = GraphNode(id: s.id, kind: kind, name: s.name,
                                    pos: SIMD3<Float>(s.x, s.y, s.z), activation: s.activation, born: 0)
            nameIndex[indexKey(kind, s.name)] = s.id
        }
        for e in snap.edges {
            guard nodes[e.a] != nil, nodes[e.b] != nil else { continue }
            let key = GraphEdge.key(e.a, e.b)
            guard !edgeKeys.contains(key) else { continue }
            edgeKeys.insert(key)
            edges.append((e.a, e.b, e.s, e.rel))
            nodes[e.a]?.degree += 1
            nodes[e.b]?.degree += 1
        }
        nextID = max(snap.nextID, (nodes.keys.max() ?? -1) + 1)
        lastOp = "resurrected · \(nodes.count) nodes"
        return !nodes.isEmpty
    }

    private func bootstrapCoreLedger() {
        do {
            let coreURL = Persist.dir.appendingPathComponent("core", isDirectory: true)
            let state = try Agent0Brain(directory: coreURL).state()
            guard state.tick > 0 else { return }

            let core = ensureNode(kind: .core, name: "self", near: .zero, activation: 1.2)
            let tick = ensureNode(kind: .percept, name: "tick-\(state.tick)", near: core.pos, activation: 1.4)
            addEdge(core.id, tick.id, 1.0, rel: "remembers")

            for concept in state.concepts.values.sorted(by: { $0.firstSeq < $1.firstSeq }) {
                let node = ensureNode(kind: .concept, name: concept.name, near: tick.pos, activation: min(1.8, 0.8 + Float(concept.seen) * 0.2))
                addEdge(tick.id, node.id, 0.9, rel: "has-concept")
            }

            for law in state.laws.values.sorted(by: { $0.key < $1.key }) {
                let src = ensureNode(kind: .concept, name: law.source, near: tick.pos, activation: 1.0)
                let dst = ensureNode(kind: .concept, name: law.target, near: src.pos, activation: 1.0)
                let lawNode = ensureNode(kind: .law, name: law.key, near: src.pos, activation: Float(law.confidence))
                addEdge(src.id, lawNode.id, Float(law.confidence), rel: "predicts")
                addEdge(lawNode.id, dst.id, Float(law.confidence), rel: "expects")
            }

            for scaffold in state.scaffolds.values.sorted(by: { $0.createdSeq < $1.createdSeq }) {
                let goal = ensureNode(kind: .goal, name: scaffold.kind, near: tick.pos, activation: scaffold.status == "materialized" ? 1.3 : 1.6)
                let target = ensureNode(kind: .concept, name: scaffold.target, near: goal.pos, activation: 0.9)
                addEdge(tick.id, goal.id, 0.9, rel: scaffold.status)
                addEdge(goal.id, target.id, 0.8, rel: "targets")
            }

            for redirect in state.redirectedConcepts.values.sorted(by: { $0.createdSeq < $1.createdSeq }) {
                removeVisibleNodes(named: redirect.concept, except: .tension)
                let tension = ensureNode(kind: .tension, name: "suppress \(redirect.concept)", near: tick.pos, activation: 1.2)
                addEdge(tick.id, tension.id, 0.8, rel: "redirects")
            }

            for redirect in state.redirectedRoutes.values.sorted(by: { $0.createdSeq < $1.createdSeq }) {
                removeVisibleNodes(named: redirect.lawKey, except: .tension)
                let tension = ensureNode(kind: .tension, name: "redirect \(redirect.lawKey)", near: tick.pos, activation: 1.4)
                addEdge(tick.id, tension.id, 1.0, rel: "redirects")
            }

            for unresolved in state.unresolvedTensions {
                let tension = ensureNode(kind: .tension, name: unresolved, near: tick.pos, activation: 1.2)
                addEdge(tick.id, tension.id, 0.8, rel: "unresolved")
            }

            lastOp = "ledger replay · ticks \(state.tick)"
            saveState()
        } catch {
            lastOp = "ledger replay fault"
        }
    }

    func apply(_ thought: ThoughtResult) {
        let core = ensureNode(kind: .core, name: "self", near: .zero, activation: 1.1)
        let tick = ensureNode(kind: .percept, name: "tick-\(thought.tick)", near: core.pos, activation: 1.4)
        addEdge(core.id, tick.id, 1.0, rel: "thinks")

        for concept in thought.concepts {
            let kind: NodeKind = thought.newConcepts.contains(concept) ? .concept : .percept
            let node = ensureNode(kind: kind, name: concept, near: tick.pos, activation: thought.newConcepts.contains(concept) ? 1.2 : 0.8)
            addEdge(tick.id, node.id, 0.9, rel: thought.newConcepts.contains(concept) ? "grows" : "sees")
        }

        for law in thought.newLaws + thought.tunedLaws {
            let src = ensureNode(kind: .concept, name: law.source, near: tick.pos, activation: 1.0)
            let dst = ensureNode(kind: .concept, name: law.target, near: src.pos, activation: 1.0)
            let lawNode = ensureNode(kind: .law, name: "\(law.source)->\(law.target)", near: src.pos, activation: 1.5)
            addEdge(src.id, lawNode.id, Float(law.confidence), rel: "predicts")
            addEdge(lawNode.id, dst.id, Float(law.confidence), rel: "expects")
        }

        for miss in thought.unmetPredictions {
            let tension = ensureNode(kind: .tension, name: "missing \(miss)", near: tick.pos, activation: 1.4)
            addEdge(tick.id, tension.id, Float(thought.predictionError), rel: "surprises")
        }

        for redirect in thought.redirectedRoutes {
            let node = ensureNode(kind: .tension, name: "redirect \(redirect.lawKey)", near: tick.pos, activation: 1.8)
            addEdge(tick.id, node.id, 1.0, rel: "redirects")
        }

        for scaffold in thought.scaffolds {
            let node = ensureNode(kind: .goal, name: scaffold.kind, near: tick.pos, activation: 1.6)
            let target = ensureNode(kind: .concept, name: scaffold.target, near: node.pos, activation: 1.1)
            addEdge(tick.id, node.id, 1.0, rel: "scaffolds")
            addEdge(node.id, target.id, 0.8, rel: "targets")
        }

        let decision = ensureNode(kind: .goal, name: thought.decision.rawValue, near: tick.pos, activation: Float(thought.confidence))
        addEdge(tick.id, decision.id, Float(thought.confidence), rel: "decides")
        lastOp = "\(thought.decision.rawValue) · surprise \(String(format: "%.2f", thought.predictionError))"
        saveState()
    }

    // MARK: - Per-frame tick

    private func step() {
        frame += 1
        for n in nodes.values { n.activation *= 0.987 }
        layout()
        if nodes.count > workingSetCap { prune() }
        sync()
        if frame % 300 == 0 { saveState() }     // ~5s heartbeat to disk — a restart can no longer kill him
        if frame % 12 == 0 {
            nodeCount = nodes.count
            edgeCount = edges.count
            ageSeconds = Int(Date().timeIntervalSince(startTime))
        }
    }

    private func prune() {
        var worstID = -1
        var worst = Float.greatestFiniteMagnitude
        for n in nodes.values where n.kind != .core {
            let score = n.activation * 2.0 + Float(n.degree) * 0.4
            if score < worst { worst = score; worstID = n.id }
        }
        guard worstID >= 0, let n = nodes[worstID] else { return }
        // consolidate to long-term memory BEFORE removing from the active graph — nothing is lost
        let neighbors = edges
            .filter { $0.a == worstID || $0.b == worstID }
            .compactMap { nodes[$0.a == worstID ? $0.b : $0.a]?.name }
        Persist.appendJSONL(
            MemoryRecord(id: n.id, kind: String(describing: n.kind), name: n.name, degree: n.degree,
                         neighbors: neighbors, archived_at_age: Int(Date().timeIntervalSince(startTime))),
            "memory.jsonl")
        let name = n.name
        removeNode(worstID)
        lastOp = "consolidate · \(name) → memory"
    }

    private func removeNode(_ id: Int) {
        let removed = nodes[id]
        nodes[id] = nil
        edges.removeAll { e in
            guard e.a == id || e.b == id else { return false }
            edgeKeys.remove(GraphEdge.key(e.a, e.b))
            let otherID = (e.a == id) ? e.b : e.a
            nodes[otherID]?.degree = max(0, (nodes[otherID]?.degree ?? 1) - 1)
            return true
        }
        if let sn = scnNodes[id] { sn.removeFromParentNode(); scnNodes[id] = nil }
        if let ln = nodeLabels[id] { ln.removeFromParentNode(); nodeLabels[id] = nil }
        if let n = removed { nameIndex[indexKey(n.kind, n.name)] = nil }
    }

    // MARK: - Layout

    private func layout() {
        let arr = Array(nodes.values)
        let n = arr.count
        guard n > 0 else { return }

        // Spatial-grid repulsion — O(n) instead of O(n²), so the graph can grow uncapped.
        // Only nodes within the cutoff R repel; cell size = R means all such pairs live in the
        // 3×3×3 neighbourhood, and each pair is applied once (j > i).
        let R: Float = 4.0
        let R2 = R * R
        @inline(__always) func cellOf(_ p: SIMD3<Float>) -> GridCell {
            GridCell(x: Int32((p.x / R).rounded(.down)),
                     y: Int32((p.y / R).rounded(.down)),
                     z: Int32((p.z / R).rounded(.down)))
        }
        var grid = [GridCell: [Int]](minimumCapacity: n)
        for i in 0..<n { grid[cellOf(arr[i].pos), default: []].append(i) }
        for i in 0..<n {
            let a = arr[i]
            let c = cellOf(a.pos)
            for dx in Int32(-1)...1 { for dy in Int32(-1)...1 { for dz in Int32(-1)...1 {
                guard let bucket = grid[GridCell(x: c.x + dx, y: c.y + dy, z: c.z + dz)] else { continue }
                for j in bucket where j > i {
                    let b = arr[j]
                    var d = a.pos - b.pos
                    var r2 = simd_length_squared(d)
                    if r2 > R2 { continue }
                    if r2 < 0.0001 {
                        d = SIMD3<Float>(.random(in: -0.1...0.1), .random(in: -0.1...0.1), .random(in: -0.1...0.1))
                        r2 = simd_length_squared(d) + 0.0001
                    }
                    let dir = d / sqrt(r2)
                    let f = kRepel / r2
                    a.vel += dir * f * dt
                    b.vel -= dir * f * dt
                }
            }}}
        }
        for e in edges {
            guard let a = nodes[e.a], let b = nodes[e.b] else { continue }
            let d = b.pos - a.pos
            let dist = simd_length(d)
            guard dist > 0.0001 else { continue }
            let dir = d / dist
            let f = kSpring * (dist - restLen) * (0.5 + e.s * 0.5)
            a.vel += dir * f * dt
            b.vel -= dir * f * dt
        }
        for a in arr {
            a.vel += (-a.pos) * kCenter * dt
            a.vel *= damping
            let sp = simd_length(a.vel)
            if sp > maxSpeed { a.vel *= (maxSpeed / sp) }
            a.pos += a.vel * dt
            if a.pos.x.isNaN || a.pos.y.isNaN || a.pos.z.isNaN {
                a.pos = SIMD3<Float>(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1))
                a.vel = .zero
            }
        }
    }

    // MARK: - Labels

    private func labelImage(_ s: String, color: NSColor) -> NSImage {
        let key = s + "|" + color.description
        if let c = labelImageCache[key] { return c }
        let font = NSFont.monospacedSystemFont(ofSize: 44, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: s, attributes: attrs)
        var size = str.size(); size.width = ceil(size.width) + 12; size.height = ceil(size.height) + 8
        let img = NSImage(size: size)
        img.lockFocus()
        str.draw(at: NSPoint(x: 6, y: 4))
        img.unlockFocus()
        labelImageCache[key] = img
        return img
    }

    private func makeLabel(_ text: String, color: NSColor, height: CGFloat) -> SCNNode {
        let img = labelImage(text, color: color)
        let aspect = img.size.width / max(img.size.height, 1)
        let plane = SCNPlane(width: height * aspect, height: height)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    // MARK: - Render sync

    private func sync() {
        // nodes + their name labels
        for (id, n) in nodes {
            let sn: SCNNode
            if let existing = scnNodes[id] {
                sn = existing
            } else {
                let sphere = SCNSphere(radius: n.kind.baseRadius)
                sphere.segmentCount = 12
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = NSColor.black
                m.emission.contents = n.kind.color
                m.blendMode = .add
                sphere.firstMaterial = m
                sn = SCNNode(geometry: sphere)
                scnNodes[id] = sn
                container.addChildNode(sn)

                let lbl = makeLabel(n.name, color: n.kind.color, height: 0.34)
                nodeLabels[id] = lbl
                container.addChildNode(lbl)
            }
            sn.position = v3(n.pos)
            let s = CGFloat(0.6 + min(n.activation, 1.6) * 0.9)
            sn.scale = SCNVector3(s, s, s)
            sn.geometry?.firstMaterial?.emission.intensity = CGFloat(0.5 + min(n.activation, 1.6))
            nodeLabels[id]?.position = v3(n.pos + SIMD3<Float>(0, Float(n.kind.baseRadius) + 0.34, 0))
        }

        // edges: one line geometry
        var verts: [SCNVector3] = []
        verts.reserveCapacity(edges.count * 2)
        for e in edges {
            guard let a = nodes[e.a], let b = nodes[e.b] else { continue }
            verts.append(v3(a.pos)); verts.append(v3(b.pos))
        }
        if verts.isEmpty {
            edgeNode.geometry = SCNGeometry()
        } else {
            let src = SCNGeometrySource(vertices: verts)
            let idx = (0..<verts.count).map { Int32($0) }
            let elem = SCNGeometryElement(indices: idx, primitiveType: .line)
            let geo = SCNGeometry(sources: [src], elements: [elem])
            let em = SCNMaterial()
            em.lightingModel = .constant
            em.diffuse.contents = NSColor(calibratedRed: 0.40, green: 0.60, blue: 1.0, alpha: 0.20)
            em.emission.contents = NSColor(calibratedRed: 0.28, green: 0.48, blue: 0.92, alpha: 1)
            em.blendMode = .add
            em.isDoubleSided = true
            geo.firstMaterial = em
            edgeNode.geometry = geo
        }

        // edge relation labels (every connection is named)
        let edgeColor = NSColor(calibratedRed: 0.62, green: 0.74, blue: 1.0, alpha: 0.9)
        var seen = Set<Int64>()
        for e in edges {
            guard let a = nodes[e.a], let b = nodes[e.b] else { continue }
            let key = GraphEdge.key(e.a, e.b)
            seen.insert(key)
            let mid = (a.pos + b.pos) * 0.5
            let ln: SCNNode
            if let ex = edgeLabels[key] { ln = ex }
            else { ln = makeLabel(e.rel, color: edgeColor, height: 0.20); edgeLabels[key] = ln; container.addChildNode(ln) }
            ln.position = v3(mid)
        }
        for (k, ln) in edgeLabels where !seen.contains(k) {
            ln.removeFromParentNode(); edgeLabels[k] = nil
        }
    }
}
