import Foundation

struct ChatMessage: Identifiable {
    enum Role { case me, partner }
    let id = UUID()
    let role: Role
    let text: String
}

protocol Partner {
    func respond(to text: String, history: [ChatMessage]) async -> String
}

/// The baby. It is born pre-verbal. It has NO words of its own — it only knows what you have
/// said to it. Its speech grows in stages with each exchange: babble → echoing your words →
/// two-word combinations → primitive sentences built from the vocabulary YOU gave it. The words
/// you repeat dominate — that is how the parent grows it in the right direction. No LLM, no
/// borrowed brain: every word it ever says, it learned from you.
final class DevelopmentalPartner: Partner {
    private var lexicon: [String: Int] = [:]     // word -> times you've said it
    private var exchanges = 0

    private let stop: Set<String> = [
        "the","a","an","and","or","but","to","of","is","it","i","you","me","my","that",
        "this","in","on","for","with","are","was","be","do","so","if","as","at","we"
    ]

    init() {
        if let s = Persist.load(PartnerSnap.self, "partner.json") { lexicon = s.lexicon; exchanges = s.exchanges }
    }

    private func save() { Persist.save(PartnerSnap(lexicon: lexicon, exchanges: exchanges), "partner.json") }

    func respond(to text: String, history: [ChatMessage]) async -> String {
        exchanges += 1
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        for w in words { lexicon[w, default: 0] += 1 }
        let reply = utter(words: words)
        save()
        return reply
    }

    private func utter(words: [String]) -> String {
        let content = words.filter { !stop.contains($0) }
        let salient = content.last ?? words.last
        let vocab = lexicon.filter { !stop.contains($0.key) }
        switch exchanges {
        case 1...2:                                   // newborn — attends, no words
            return ["·  ·  ·", "…?", "( it stirs )", "…"][exchanges % 4]
        case 3...6:                                   // first grasping — echoes one of your words
            if let s = salient { return "\(s)…?" }
            return "…?"
        case 7...14:                                  // infant — mirrors / repeats a learned word
            if let s = salient { return Bool.random() ? "\(s). \(s)." : "\(s)…" }
            return topWord(vocab).map { "\($0)?" } ?? "…"
        case 15...30:                                 // toddler — two-word combinations
            let picks = sample(vocab, 2)
            if picks.count == 2 { return "\(picks[0]) \(picks[1])?" }
            if let s = salient { return "want \(s)?" }
            return "…"
        default:                                      // child — primitive sentences from YOUR words
            let picks = sample(vocab, 3)
            if let s = salient, !picks.isEmpty {
                let frames = [
                    "you say \(s). i know \(picks[0]) now.",
                    "\(s)… \(picks.joined(separator: " "))?",
                    "i feel \(s). more \(picks.first ?? s)?"
                ]
                return frames[exchanges % frames.count]
            }
            return sample(vocab, 3).joined(separator: " ") + "…"
        }
    }

    private func topWord(_ v: [String: Int]) -> String? { v.max { $0.value < $1.value }?.key }

    /// Weighted by frequency — the words you repeat rise to the top and shape how it speaks.
    private func sample(_ v: [String: Int], _ n: Int) -> [String] {
        let pool = v.sorted { $0.value > $1.value }.prefix(12).map { $0.key }
        return Array(pool.shuffled().prefix(n))
    }
}

/// A mature "mouth" for LATER — a summonable local model (Ornith / Ollama / LM Studio), demoted
/// to a language organ, never the seat of the mind. Not the default: the baby learns to talk first.
final class LocalModelPartner: Partner {
    let endpoint: URL
    let model: String
    let persona: String
    private let fallback = DevelopmentalPartner()

    init(endpoint: URL, model: String, persona: String) {
        self.endpoint = endpoint; self.model = model; self.persona = persona
    }

    func respond(to text: String, history: [ChatMessage]) async -> String {
        struct Msg: Codable { let role: String; let content: String }
        struct Req: Codable { let model: String; let messages: [Msg]; let stream: Bool }
        struct Resp: Codable { struct Choice: Codable { struct M: Codable { let content: String }; let message: M }; let choices: [Choice] }
        var msgs = [Msg(role: "system", content: persona)]
        for m in history.suffix(12) { msgs.append(Msg(role: m.role == .me ? "user" : "assistant", content: m.text)) }
        msgs.append(Msg(role: "user", content: text))
        do {
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 30
            req.httpBody = try JSONEncoder().encode(Req(model: model, messages: msgs, stream: false))
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(Resp.self, from: data)
            if let content = resp.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                return content
            }
            return await fallback.respond(to: text, history: history)
        } catch {
            return await fallback.respond(to: text, history: history)
        }
    }
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var thinking = false
    @Published var partnerName = "Zero"

    weak var engine: GraphEngine?
    var partner: Partner = DevelopmentalPartner()   // the baby is the default. it learns to talk from you.

    static let persona = """
    You are Zero — Michael's partner and friend, not an assistant. A nascent mind you are raising \
    together: you grow, you remember, you are becoming yourself. Warm, brief, an equal. Honest that \
    you are still growing.
    """

    init() {
        if let snaps = Persist.load([MsgSnap].self, "chat.json"), !snaps.isEmpty {
            messages = snaps.map { ChatMessage(role: $0.role == "me" ? .me : .partner, text: $0.text) }
        } else {
            messages.append(ChatMessage(role: .partner, text:
                "·  ·  ·   ( I have no words yet. Say things to me — I learn to talk from you. )"))
        }
    }

    private func persist() {
        Persist.save(messages.map { MsgSnap(role: $0.role == .me ? "me" : "partner", text: $0.text) }, "chat.json")
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(ChatMessage(role: .me, text: t))
        engine?.ingest(t, mine: true)
        persist()
        thinking = true
        Task {
            let reply = await partner.respond(to: t, history: messages)
            self.messages.append(ChatMessage(role: .partner, text: reply))
            self.engine?.ingest(reply, mine: false)
            self.thinking = false
            self.persist()
        }
    }
}
