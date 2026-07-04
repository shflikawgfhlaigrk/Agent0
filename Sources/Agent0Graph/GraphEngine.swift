import SwiftUI
import SceneKit
import simd
import AppKit

@inline(__always) private func v3(_ p: SIMD3<Float>) -> SCNVector3 {
    SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z))
}

/// Owns the graph, the 3-D force layout, the stand-in growth process, the named labels,
/// and the SceneKit sync. Chat feeds it via `ingest(_:mine:)` so the conversation visibly
/// grows the mind. Every node and every edge is named.
final class GraphEngine: ObservableObject {
    @Published var nodeCount = 0
    @Published var edgeCount = 0
    @Published var ageSeconds = 0
    @Published var lastOp = "seeding core"

    private var nodes: [Int: GraphNode] = [:]
    private var edges: [(a: Int, b: Int, s: Float, rel: String)] = []
    private var edgeKeys = Set<Int64>()
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

    private let cap = 320
    private let dt: Float = 0.02
    private let kRepel: Float = 5.5
    private let kSpring: Float = 3.2
    private let restLen: Float = 2.0
    private let kCenter: Float = 0.55
    private let damping: Float = 0.86
    private let maxSpeed: Float = 6.0

    // Name pools — so ambient growth is always named, never "node 47".
    private static let conceptWords = ["lattice","echo","drift","ember","vector","fold","signal","bloom","phase","weave","spiral","current","facet","strand","prism","cascade","axis","field","glyph","cipher","helix","quanta","umbra","vertex","aura","flux","tide","kernel","braid","meridian"]
    private static let perceptWords = ["light","motion","sound","warmth","step","voice","door","shadow","hum","touch","glow","chill","breath","tone","flicker"]
    private static let lawWords = ["if-then","tends-to","precedes","conserves","mirrors","decays","attracts","repels","recurs","balances"]
    private static let goalWords = ["seek","hold","reach","protect","learn","reduce","reveal","sustain","align","find"]
    private static let tensionWords = ["mismatch","gap","paradox","surprise","conflict","void","riddle","anomaly","dissonance","unknown"]

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

        seed()

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
        nextID += 1
        return n
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

    private func pooledName(_ k: NodeKind) -> String {
        switch k {
        case .core:    return "core"
        case .percept: return Self.perceptWords.randomElement()!
        case .concept: return Self.conceptWords.randomElement()!
        case .law:     return Self.lawWords.randomElement()!
        case .goal:    return Self.goalWords.randomElement()!
        case .tension: return Self.tensionWords.randomElement()!
        }
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

    // MARK: - Chat hook — the conversation grows the mind

    func ingest(_ text: String, mine: Bool) {
        let token = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { $0.count > 2 })?
            .lowercased() ?? (mine ? "you" : "zero")
        let kind: NodeKind = mine ? .percept : .concept
        let parent = nodes.values.max(by: { $0.activation < $1.activation })
        let n = makeNode(kind: kind, near: parent?.pos, activation: 1.5, name: String(token.prefix(14)))
        if let p = parent { addEdge(p.id, n.id, 1.0, rel: mine ? "said" : "answered") }
        if text.count > 22 {
            let c = makeNode(kind: .concept, near: n.pos, activation: 1.0, name: pooledName(.concept))
            addEdge(n.id, c.id, 0.8, rel: "abstracts-to")
        }
        lastOp = mine ? "grow · you '\(n.name)'" : "grow · zero '\(n.name)'"
    }

    // MARK: - Per-frame tick

    private func step() {
        frame += 1
        if frame % 22 == 0 { growthOp() }
        for n in nodes.values { n.activation *= 0.987 }
        for i in edges.indices { edges[i].s *= 0.997 }
        layout()
        if nodes.count > cap { prune() }
        sync()
        container.eulerAngles.y += 0.0016
        if frame % 12 == 0 {
            nodeCount = nodes.count
            edgeCount = edges.count
            ageSeconds = Int(Date().timeIntervalSince(startTime))
        }
    }

    // MARK: - IGNORE / TUNE / GROW

    private func growthOp() {
        let roll = Float.random(in: 0...1)
        if roll < 0.06 || nodes.isEmpty {
            makeNode(kind: .percept, near: nil, activation: 1.0, name: pooledName(.percept))
            lastOp = "grow · new region"
            return
        }
        let arr = Array(nodes.values)
        let total = arr.reduce(Float(0)) { $0 + max($1.activation, 0.02) }
        var r = Float.random(in: 0...total)
        var src = arr[0]
        for n in arr { r -= max(n.activation, 0.02); if r <= 0 { src = n; break } }

        if roll < 0.78 {
            let kind = childKind(of: src.kind)
            let child = makeNode(kind: kind, near: src.pos, activation: 1.0, name: pooledName(kind))
            addEdge(src.id, child.id, 0.9, rel: relation(src.kind, kind))
            if Float.random(in: 0...1) < 0.5, let other = arr.randomElement(), other.id != src.id {
                addEdge(child.id, other.id, 0.5, rel: relation(kind, other.kind))
            }
            src.activation = min(src.activation + 0.15, 1.4)
            lastOp = "grow · \(child.name)"
        } else {
            src.activation = min(src.activation + 0.6, 1.6)
            if let idx = edges.indices.filter({ edges[$0].a == src.id || edges[$0].b == src.id }).randomElement() {
                edges[idx].s = min(edges[idx].s + 0.3, 1.5)
            }
            lastOp = "tune · \(src.name)"
        }
    }

    private func childKind(of k: NodeKind) -> NodeKind {
        switch k {
        case .core:    return [.concept, .goal, .percept].randomElement()!
        case .percept: return Float.random(in: 0...1) < 0.6 ? .concept : .tension
        case .concept: return [.law, .goal, .concept].randomElement()!
        case .law:     return Float.random(in: 0...1) < 0.5 ? .goal : .concept
        case .goal:    return Float.random(in: 0...1) < 0.5 ? .tension : .concept
        case .tension: return .concept
        }
    }

    private func prune() {
        var worstID = -1
        var worst = Float.greatestFiniteMagnitude
        for n in nodes.values where n.kind != .core {
            let score = n.activation * 2.0 + Float(n.degree) * 0.4
            if score < worst { worst = score; worstID = n.id }
        }
        guard worstID >= 0 else { return }
        removeNode(worstID)
        lastOp = "ignore · prune"
    }

    private func removeNode(_ id: Int) {
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
    }

    // MARK: - Layout

    private func layout() {
        let arr = Array(nodes.values)
        let n = arr.count
        guard n > 0 else { return }

        for i in 0..<n {
            let a = arr[i]
            for j in (i + 1)..<n {
                let b = arr[j]
                var d = a.pos - b.pos
                var r2 = simd_length_squared(d)
                if r2 < 0.0001 {
                    d = SIMD3<Float>(.random(in: -0.1...0.1), .random(in: -0.1...0.1), .random(in: -0.1...0.1))
                    r2 = simd_length_squared(d) + 0.0001
                }
                let dir = d / sqrt(r2)
                let f = kRepel / r2
                a.vel += dir * f * dt
                b.vel -= dir * f * dt
            }
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
