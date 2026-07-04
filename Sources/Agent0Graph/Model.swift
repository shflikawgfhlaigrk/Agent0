import Foundation
import simd
import AppKit

/// The kinds of thing a mind-node can be. Colour-coded so the graph reads at a glance.
enum NodeKind: Int, CaseIterable {
    case core       // innate self / identity — never pruned
    case percept    // raw sensation / something you said, entering the stream
    case concept    // an abstraction the mind grew
    case law        // a learned predictive rule
    case goal       // something it is trying to bring about
    case tension    // an unresolved contradiction / surprise

    var color: NSColor {
        switch self {
        case .core:    return NSColor(calibratedRed: 1.00, green: 0.98, blue: 0.90, alpha: 1)
        case .percept: return NSColor(calibratedRed: 0.20, green: 0.80, blue: 1.00, alpha: 1)
        case .concept: return NSColor(calibratedRed: 0.62, green: 0.40, blue: 1.00, alpha: 1)
        case .law:     return NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.25, alpha: 1)
        case .goal:    return NSColor(calibratedRed: 0.30, green: 1.00, blue: 0.60, alpha: 1)
        case .tension: return NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.32, alpha: 1)
        }
    }

    var baseRadius: CGFloat {
        switch self {
        case .core:                  return 0.42
        case .concept, .law, .goal:  return 0.26
        case .tension:               return 0.22
        case .percept:               return 0.20
        }
    }
}

/// One node in the living graph. A reference type so the physics loop can mutate it in place.
/// Every node carries a name — nothing in this mind is anonymous.
final class GraphNode {
    let id: Int
    var kind: NodeKind
    var name: String
    var pos: SIMD3<Float>
    var vel: SIMD3<Float> = .zero
    var activation: Float
    var degree: Int = 0
    let born: TimeInterval

    init(id: Int, kind: NodeKind, name: String, pos: SIMD3<Float>, activation: Float, born: TimeInterval) {
        self.id = id
        self.kind = kind
        self.name = name
        self.pos = pos
        self.activation = activation
        self.born = born
    }
}

/// An undirected weighted, **named** link. Keyed by endpoint pair so we never duplicate.
enum GraphEdge {
    static func key(_ x: Int, _ y: Int) -> Int64 {
        let lo = Int64(min(x, y)); let hi = Int64(max(x, y))
        return (lo << 32) | hi
    }
}
