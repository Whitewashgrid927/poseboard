import Foundation

enum PromptRole: String, Codable, CaseIterable, Sendable {
    case instruction, modifier
    var label: String { self == .instruction ? "Instruction" : "Modifier" }
}

enum PromptText {
    static let limit = 24_000
    static func validate(_ text: String, limit: Int = limit) throws {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.count <= limit,
              text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || "\n\r\t".unicodeScalars.contains($0) }) else {
            throw PoseError("Use plain text with paragraphs, up to \(limit) characters. Invisible control characters are not accepted.")
        }
    }
}

enum PromptDepth: Int, CaseIterable, Sendable {
    case original, concise, balanced, detailed
    var label: String {
        switch self { case .original: "As written"; case .concise: "Concise"; case .balanced: "Balanced"; case .detailed: "Detailed" }
    }
    var instruction: String? {
        switch self {
        case .original: nil
        case .concise: "Keep the response concise and focused on the essential points."
        case .balanced: "Give a balanced explanation with enough detail to make the reasoning clear."
        case .detailed: "Explain in depth, including the reasoning, relevant examples, and tradeoffs."
        }
    }
}

struct PromptPart: Identifiable, Equatable, Sendable {
    var id = UUID()
    let meaningID: UUID
    let name: String
    let body: String
    let symbol: MeaningSymbol
    let role: PromptRole
}

/// A deterministic composer. Saved instructions are joined verbatim, never rewritten by a model.
struct PromptComposer: Equatable, Sendable {
    private(set) var parts: [PromptPart] = []
    private(set) var depth = PromptDepth.original
    private(set) var context = ""
    private(set) var editedText: String?
    private(set) var revision = UUID()
    var text: String {
        if let editedText { return editedText }
        var blocks = parts.map(\.body)
        if !parts.isEmpty, let instruction = depth.instruction { blocks.append(instruction) }
        if !context.isEmpty { blocks.append("Context supplied for this prompt:\n" + context) }
        return blocks.joined(separator:"\n\n")
    }
    var isEmpty: Bool { text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
    var isEdited: Bool { editedText != nil }
    mutating func add(_ meaning: Meaning) throws {
        guard !isEdited else { throw PoseError("This draft has manual edits. Keep editing it, or choose Use signs to return to your sign composition.") }
        guard parts.count < 12 else { throw PoseError("A prompt can combine up to 12 signs. Undo a sign or start a new prompt.") }
        try meaning.validate()
        var candidate = self
        candidate.parts.append(.init(meaningID:meaning.id,name:meaning.text,body:meaning.body,symbol:meaning.symbol,role:meaning.promptRole))
        try PromptText.validate(candidate.text)
        candidate.revision = UUID(); self = candidate
    }
    mutating func setDepth(_ value: PromptDepth) throws {
        guard !isEdited else { throw PoseError("Choose Use signs before changing depth.") }
        var candidate = self; candidate.depth = value
        if !candidate.isEmpty { try PromptText.validate(candidate.text) }
        candidate.revision = UUID(); self = candidate
    }
    mutating func setContext(_ value: String) throws {
        guard !isEdited else { throw PoseError("Choose Use signs before changing context.") }
        if !value.isEmpty { try PromptText.validate(value,limit:8_000) }
        var candidate = self; candidate.context = value
        if !candidate.isEmpty { try PromptText.validate(candidate.text) }
        candidate.revision = UUID(); self = candidate
    }
    mutating func edit(_ value: String) throws {
        try PromptText.validate(value)
        editedText = value; revision = UUID()
    }
    mutating func useSigns() { editedText = nil; revision = UUID() }
    mutating func undo() {
        guard !isEdited, !parts.isEmpty else { return }
        parts.removeLast(); revision = UUID()
    }
    mutating func clear() { self = .init() }
}

/// Only continuous fresh frames with zero detected hands rearm a held sign.
/// Missing callbacks, extra hands, and low-confidence observed hands cannot count as release.
struct SignLatch {
    private(set) var needsRelease = false
    private var neutralSince: Double?
    private var last = 0.0
    mutating func reset(requiringRelease: Bool = false) { self = .init(); needsRelease = requiringRelease }
    mutating func observe(_ frame: PoseFrame, now: Double) {
        guard frame.time.isFinite, now.isFinite, now >= frame.time, now-frame.time <= 0.30, frame.time > last else {
            neutralSince = nil; return
        }
        let continuous = last > 0 && frame.time-last <= 0.22
        last = frame.time
        guard needsRelease, frame.detectedCount == 0, frame.hands.isEmpty else { neutralSince = nil; return }
        if neutralSince == nil || !continuous { neutralSince = frame.time }
        if frame.time-(neutralSince ?? frame.time) >= 0.45 { needsRelease = false; neutralSince = nil }
    }
    mutating func accept(_ stableID: UUID?) -> UUID? {
        guard !needsRelease, let stableID else { return nil }
        needsRelease = true; neutralSince = nil; return stableID
    }
}

enum DeliveryDestination: Equatable, Sendable {
    case clipboard
    case service(UUID)
}

struct PromptReview: Identifiable, Equatable, Sendable {
    let id = UUID()
    let revision: UUID
    let text: String
    let destination: DeliveryDestination
    let createdAt: Double
    func validate(composer: PromptComposer, destination: DeliveryDestination, now: Double) throws {
        guard revision == composer.revision, text == composer.text, self.destination == destination,
              now.isFinite, now >= createdAt, now-createdAt < 90 else {
            throw PoseError("This confirmation has expired or the draft changed. Review the prompt again.")
        }
        try PromptText.validate(text)
    }
}
