import SwiftUI
import SceneKit
import AppKit

// MARK: - Orbit camera: drag to orbit, multiplicative scroll-zoom, pinch. Replaces SceneKit's janky default.
final class OrbitSCNView: SCNView {
    private var yaw: CGFloat = 0.3
    private var pitch: CGFloat = 0.22
    private var distance: CGFloat = 26
    private let pivot = SCNNode()
    private let camNode = SCNNode()

    func installCamera(in scene: SCNScene) {
        let cam = SCNCamera()
        cam.wantsHDR = true
        cam.bloomIntensity = 1.35
        cam.bloomThreshold = 0.35
        cam.bloomBlurRadius = 14
        cam.zNear = 0.1
        cam.zFar = 900
        cam.fieldOfView = 55
        camNode.camera = cam
        pivot.addChildNode(camNode)
        scene.rootNode.addChildNode(pivot)
        pointOfView = camNode
        apply()
    }

    private func apply() {
        pitch = max(-1.45, min(1.45, pitch))
        distance = max(5, min(150, distance))
        pivot.eulerAngles = SCNVector3(pitch, yaw, 0)
        camNode.position = SCNVector3(0, 0, distance)
    }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func mouseDragged(with event: NSEvent) {
        yaw += event.deltaX * 0.008
        pitch += event.deltaY * 0.008
        apply()
    }

    override func scrollWheel(with event: NSEvent) {
        let d = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.06
        distance *= CGFloat(exp(-d))     // multiplicative = smooth at every distance
        apply()
    }

    override func magnify(with event: NSEvent) {
        distance *= CGFloat(1.0 - event.magnification)
        apply()
    }
}

struct GraphSceneView: NSViewRepresentable {
    let engine: GraphEngine
    func makeNSView(context: Context) -> OrbitSCNView {
        let v = OrbitSCNView()
        engine.attach(to: v)
        return v
    }
    func updateNSView(_ nsView: OrbitSCNView, context: Context) {}
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var engine = GraphEngine()
    @StateObject private var chat = ChatModel()

    var body: some View {
        HStack(spacing: 0) {
            ChatPanel(chat: chat).frame(width: 380)
            ZStack(alignment: .topLeading) {
                GraphSceneView(engine: engine).ignoresSafeArea()
                GraphStats(engine: engine).padding(12)
            }
        }
        .background(Color.black)
        .onAppear { chat.engine = engine }
    }
}

// MARK: - Chat

struct ChatPanel: View {
    @ObservedObject var chat: ChatModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(chat.messages) { bubble($0) }
                        if chat.thinking {
                            Text("\(chat.partnerName) is thinking…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .padding(14)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(chat.messages.last?.id, anchor: .bottom) }
                }
            }
            inputBar
        }
        .background(Color(red: 0.03, green: 0.035, blue: 0.06))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4), Color(red: 0.9, green: 0.7, blue: 0.2)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 26)
                .overlay(Text("0").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.black))
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.partnerName).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                Text("your partner · growing").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(12)
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack(spacing: 0) {
            if m.role == .me { Spacer(minLength: 40) }
            Text(m.text)
                .font(.system(size: 13))
                .foregroundStyle(m.role == .me ? Color.black.opacity(0.9) : Color.white.opacity(0.9))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(m.role == .me ? Color(red: 1, green: 0.80, blue: 0.3) : Color.white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 270, alignment: m.role == .me ? .trailing : .leading)
            if m.role == .partner { Spacer(minLength: 40) }
        }
        .id(m.id)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("talk to \(chat.partnerName)…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .focused($focused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(red: 1, green: 0.80, blue: 0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private func send() {
        chat.send(draft)
        draft = ""
        focused = true
    }
}

// MARK: - Graph stats overlay

struct GraphStats: View {
    @ObservedObject var engine: GraphEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIVING GRAPH").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            row("nodes", "\(engine.nodeCount)")
            row("edges", "\(engine.edgeCount)")
            row("age", "\(engine.ageSeconds)s")
            row("last", engine.lastOp)
            Spacer().frame(height: 6)
            legend
            Spacer().frame(height: 6)
            Text("drag to orbit · scroll to zoom").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(10)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
            Text(v).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.82))
        }
    }
    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            leg(Color(red: 1, green: 0.98, blue: 0.90), "core")
            leg(Color(red: 0.20, green: 0.80, blue: 1), "percept")
            leg(Color(red: 0.62, green: 0.40, blue: 1), "concept")
            leg(Color(red: 1, green: 0.80, blue: 0.25), "law")
            leg(Color(red: 0.30, green: 1, blue: 0.60), "goal")
            leg(Color(red: 1, green: 0.42, blue: 0.32), "tension")
        }
    }
    private func leg(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
        }
    }
}
