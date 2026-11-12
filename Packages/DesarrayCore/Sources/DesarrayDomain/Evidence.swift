import CoreGraphics
import Foundation

/// Core product contract (PRD §7): every value says how we know it.
public enum EvidenceKind: String, Codable, Sendable {
    /// Returned directly by a source or measured from user input / a captured artifact.
    case observed
    /// Computed from observations (gaps, insets, pixel equivalents, estimates).
    case inferred
    /// Higher-level summary across many observations (rhythms, tokens, profiles).
    case interpreted
}

public enum EvidenceSource: String, Codable, Sendable {
    case selectionGeometry
    case accessibility
    case visual
    case browser
    case imported
    case derived
}

public enum CoordinateSpace: String, Codable, Sendable {
    /// Global desktop, origin at top-left of the primary display, logical points (CG/AX convention).
    case globalTopLeftPoints
    case displayPixels
}

public struct Provenance: Codable, Hashable, Sendable {
    public var kind: EvidenceKind
    public var source: EvidenceSource
    /// API/property or algorithm identifier, versioned where it matters, e.g. "pointer-drag/1".
    public var method: String
    public var capturedAt: Date
    public var coordinateSpace: CoordinateSpace?
    public var unit: String?
    public var limitations: [String]

    public init(kind: EvidenceKind, source: EvidenceSource, method: String, capturedAt: Date = .now,
                coordinateSpace: CoordinateSpace? = nil, unit: String? = nil, limitations: [String] = []) {
        self.kind = kind
        self.source = source
        self.method = method
        self.capturedAt = capturedAt
        self.coordinateSpace = coordinateSpace
        self.unit = unit
        self.limitations = limitations
    }
}

/// A user-drawn rectangle. Phase 1's only observation.
public struct Selection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Global top-left logical points.
    public var rect: CGRect
    public var displayID: UInt32
    public var displayName: String
    /// Backing scale of `displayID` at capture time (px per pt).
    public var backingScale: CGFloat
    /// True when the drag crossed off the starting display and was clipped to it (DECISIONS D3).
    public var clipped: Bool
    public var provenance: Provenance

    public init(id: UUID = UUID(), rect: CGRect, displayID: UInt32, displayName: String,
                backingScale: CGFloat, clipped: Bool, capturedAt: Date = .now) {
        self.id = id
        self.rect = rect
        self.displayID = displayID
        self.displayName = displayName
        self.backingScale = backingScale
        self.clipped = clipped
        self.provenance = Provenance(
            kind: .observed, source: .selectionGeometry, method: "pointer-drag/1",
            capturedAt: capturedAt, coordinateSpace: .globalTopLeftPoints, unit: "pt",
            limitations: clipped ? ["Clipped to \(displayName); selection crossed a display edge."] : []
        )
    }
}
