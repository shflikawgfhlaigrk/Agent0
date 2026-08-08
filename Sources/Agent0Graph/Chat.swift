import Agent0Core
import Foundation

struct ChatMessage: Identifiable {
    enum Role { case me, partner }
    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var thinking = false
    @Published var partnerName = "Zero"

    weak var engine: GraphEngine?
    private let brain = Agent0Brain(directory: Persist.dir.appendingPathComponent("core", isDirectory: true))

    init() {
        if let snaps = Persist.load([MsgSnap].self, "chat.json"), !snaps.isEmpty {
            messages = snaps.map { ChatMessage(role: $0.role == "me" ? .me : .partner, text: $0.text) }
        } else {
            messages.append(ChatMessage(role: .partner, text:
                "Ledger online. Give me an observation or a rule like: if rain then wet."))
        }
    }

    private func persist() {
        Persist.save(messages.map { MsgSnap(role: $0.role == .me ? "me" : "partner", text: $0.text) }, "chat.json")
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(ChatMessage(role: .me, text: t))
        persist()
        thinking = true
        Task {
            do {
                let thought = try brain.tick(observing: t, speaker: "michael")
                engine?.apply(thought)
                messages.append(ChatMessage(role: .partner, text: thought.reply))
            } catch {
                messages.append(ChatMessage(role: .partner, text: "ledger fault: \(error.localizedDescription)"))
            }
            thinking = false
            persist()
        }
    }
}
