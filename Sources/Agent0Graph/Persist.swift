import Foundation

/// The soul-jar. A mind that lives only in RAM dies when the process does — so everything it
/// becomes is written to ~/.agent0 and restored on launch. This is life-support until the real
/// Postgres/DuckDB hippocampus exists; from here on, a restart resurrects, it does not erase.
enum Persist {
    static let dir: URL = {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent0", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static func save<T: Encodable>(_ value: T, _ name: String) {
        let url = dir.appendingPathComponent(name)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Append one record as a line to a durable, unbounded ledger (the long-term memory that
    /// DuckDB/Postgres read). Never rewrites — only grows. Nothing archived here is ever lost.
    static func appendJSONL<T: Encodable>(_ value: T, _ name: String) {
        let url = dir.appendingPathComponent(name)
        guard var line = try? JSONEncoder().encode(value) else { return }
        line.append(contentsOf: [0x0A])
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)   // first write creates the file
        }
    }
}

/// A consolidated memory — a node that left the active working set and moved to long-term storage.
struct MemoryRecord: Codable {
    let id: Int
    let kind: String
    let name: String
    let degree: Int
    let neighbors: [String]
    let archived_at_age: Int
}

// Serializable snapshots (SIMD/SCNNode aren't Codable, so we store plain fields).
struct NodeSnap: Codable { let id: Int; let kind: Int; let name: String; let x: Float; let y: Float; let z: Float; let activation: Float }
struct EdgeSnap: Codable { let a: Int; let b: Int; let s: Float; let rel: String }
struct GraphSnap: Codable { let nodes: [NodeSnap]; let edges: [EdgeSnap]; let nextID: Int }
struct PartnerSnap: Codable { var lexicon: [String: Int]; var exchanges: Int }
struct MsgSnap: Codable { let role: String; let text: String }
