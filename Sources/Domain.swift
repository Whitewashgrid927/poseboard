import Foundation

struct PoseError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
struct Vector: Codable, Equatable, Sendable {
    var x: Double; var y: Double
    var length: Double { hypot(x, y) }
    var finite: Bool { x.isFinite && y.isFinite }
    static func + (a: Self, b: Self) -> Self { .init(x: a.x+b.x, y: a.y+b.y) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x-b.x, y: a.y-b.y) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x*b, y: a.y*b) }
}
struct Joint: Sendable { var point: Vector; var confidence: Double }
struct ObservedHand: Sendable { var joints: [Joint?] }
struct PoseFrame: Sendable {
    var time: Double = 0
    var hands: [ObservedHand] = []
    var detectedCount = 0
    var width: Double = 1280; var height: Double = 720
}

/// Normalized 2D landmarks only. No image, camera identifier, or body/face data.
struct PoseSignature: Codable, Equatable, Sendable {
    var first: [Vector?]
    var second: [Vector?]
    var separation: Vector
    static let anchors = [0, 5, 9, 17]
    func validate() throws {
        for hand in [first, second] {
            guard hand.count == 21, hand.compactMap({ $0 }).count >= 16,
                  Self.anchors.allSatisfy({ hand[$0] != nil }),
                  hand.compactMap({ $0 }).allSatisfy({ $0.finite && abs($0.x) <= 8 && abs($0.y) <= 8 }) else { throw PoseError("This pose has invalid hand landmarks.") }
            for start in [1, 5, 9, 13, 17] {
                guard hand[start..<(start+4)].compactMap({ $0 }).count >= 2 else { throw PoseError("A pose is missing finger landmarks.") }
            }
        }
        guard separation.finite, separation.length >= 0.45, separation.length <= 16 else { throw PoseError("This pose has invalid hand spacing.") }
    }
    /// Preserve hand orientation and relative spacing; remove camera distance and whole-pose translation.
    static func make(_ frame: PoseFrame) -> Self? {
        guard frame.detectedCount == 2, frame.hands.count == 2, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return nil }
        let aspect = frame.width / frame.height
        var measured: [(points: [Vector?], center: Vector, scale: Double)] = []
        for hand in frame.hands {
            guard hand.joints.count == 21 else { return nil }
            let points = hand.joints.map { joint -> Vector? in
                guard let joint, joint.confidence.isFinite, joint.confidence >= 0.35, joint.confidence <= 1,
                      joint.point.finite, (0...1).contains(joint.point.x), (0...1).contains(joint.point.y) else { return nil }
                return .init(x: joint.point.x * aspect, y: joint.point.y)
            }
            guard let wrist = points[0], let index = points[5], let middle = points[9], let little = points[17] else { return nil }
            let scale = ((middle-wrist).length + (little-index).length) / 2
            guard scale >= 0.035, scale <= 0.6 else { return nil }
            let center = (wrist+index+middle+little)*0.25
            measured.append((points.map { $0.map { ($0-wrist)*(1/scale) } }, center, scale))
        }
        // Preview-left/preview-right is deterministic; uncertain Vision handedness cannot swap a learned pose.
        measured.sort { $0.center.x < $1.center.x }
        let a = measured[0], b = measured[1], scale = (a.scale+b.scale)/2
        guard abs(a.center.x-b.center.x) > scale*0.25, max(a.scale,b.scale)/min(a.scale,b.scale) < 2.2 else { return nil }
        let signature = Self(first: a.points, second: b.points, separation: (b.center-a.center)*(1/scale))
        return (try? signature.validate()) != nil ? signature : nil
    }
    static func distance(_ a: Self, _ b: Self) -> Double {
        var squares = 0.0, weight = 0.0, worstFinger = 0.0
        for (left, right) in [(a.first,b.first), (a.second,b.second)] {
            guard left.count == 21, right.count == 21 else { return .infinity }
            let shared = (0..<21).filter { left[$0] != nil && right[$0] != nil }
            guard shared.count >= 15, Double(shared.count) >= Double(max(left.compactMap{$0}.count, right.compactMap{$0}.count))*0.8 else { return .infinity }
            for start in [1,5,9,13,17] {
                let indices = (start..<(start+4)).filter { left[$0] != nil && right[$0] != nil }
                guard indices.count >= 2 else { return .infinity }
                var finger = 0.0
                for i in indices {
                    let distance = (left[i]!-right[i]!).length, w = (i-start == 3) ? 2.0 : 1.0
                    squares += distance*distance*w; weight += w; finger += distance
                }
                worstFinger = max(worstFinger, finger/Double(indices.count))
            }
        }
        guard weight > 0 else { return .infinity }
        return 0.55*sqrt(squares/weight) + 0.30*worstFinger + 0.15*min(3,(a.separation-b.separation).length)
    }
    static func average(_ samples: [Self]) -> Self? {
        guard !samples.isEmpty else { return nil }
        func points(_ key: KeyPath<Self,[Vector?]>) -> [Vector?] {
            (0..<21).map { index in
                let values = samples.compactMap { $0[keyPath: key][index] }
                guard values.count*4 >= samples.count*3 else { return nil }
                return values.reduce(Vector(x:0,y:0),+) * (1/Double(values.count))
            }
        }
        let result = Self(first: points(\.first), second: points(\.second), separation: samples.map(\.separation).reduce(.init(x:0,y:0),+) * (1/Double(samples.count)))
        return (try? result.validate()) != nil ? result : nil
    }
}

enum MeaningSymbol: String, Codable, CaseIterable, Sendable {
    case greeting = "hand.wave", yes = "checkmark", no = "xmark", thanks = "heart", pause = "pause", help = "lifepreserver", water = "drop", happy = "sun.max", home = "house", question = "questionmark", person = "person", star = "star"
    var label: String { switch self { case .greeting: "Hello"; case .yes: "Yes"; case .no: "No"; case .thanks: "Thanks"; case .pause: "Break"; case .help: "Help"; case .water: "Water"; case .happy: "Happy"; case .home: "Home"; case .question: "Question"; case .person: "Person"; case .star: "Star" } }
}
struct Meaning: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var symbol: MeaningSymbol
    var examples: [PoseSignature] = []
    var tolerance = 0.15
    // Optional fields decode older vocabularies without changing their stored text or poses.
    var prompt: String?
    var role: PromptRole?
    var body: String { prompt ?? text }
    var promptRole: PromptRole { role ?? .instruction }
    var learned: Bool { examples.count == 3 }
    func score(_ signature: PoseSignature) -> Double {
        guard learned else { return .infinity }
        let values = examples.map { PoseSignature.distance(signature,$0) }.sorted()
        return (values[0]+values[1])/2
    }
    func validate() throws {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.count <= 100,
              text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              examples.isEmpty || examples.count == 3, tolerance.isFinite, (0.12...0.24).contains(tolerance) else { throw PoseError("This vocabulary entry is invalid.") }
        for example in examples { try example.validate() }
        try PromptText.validate(body, limit:8_000)
    }
}
struct Vocabulary: Codable, Equatable, Sendable {
    var version = 2
    var meanings: [Meaning]
    static var starter: Self { .init(meanings: []) }
    func validate() throws {
        guard [1,2].contains(version), meanings.count <= 100, Set(meanings.map(\.id)).count == meanings.count else { throw PoseError("This vocabulary is invalid or from a newer app version.") }
        for meaning in meanings { try meaning.validate() }
    }
    func match(_ signature: PoseSignature) -> UUID? {
        let ranked = meanings.filter(\.learned).map { ($0,$0.score(signature)) }.sorted { $0.1 < $1.1 }
        guard let best = ranked.first, best.1.isFinite, best.1 <= best.0.tolerance else { return nil }
        if ranked.count > 1, ranked[1].1-best.1 < 0.055 { return nil }
        return best.0.id
    }
    func conflict(with meaning: Meaning) -> Meaning? {
        meanings.first { other in
            guard other.id != meaning.id, other.learned else { return false }
            let distance = meaning.examples.map { other.score($0) }.min() ?? .infinity
            return distance < max(other.tolerance,meaning.tolerance)+0.045
        }
    }
}

struct StableMatch {
    private var candidate: UUID?
    private var since = 0.0
    private var last = 0.0
    private var frames = 0
    mutating func reset() { self = .init() }
    mutating func update(_ id: UUID?, time: Double, now: Double) -> UUID? {
        guard time.isFinite, now.isFinite, now-time >= 0, now-time <= 0.30, time > last, let id else { reset(); return nil }
        if candidate != id || time-last > 0.22 { candidate = id; since = time; frames = 0 }
        last = time; frames += 1
        return frames >= 6 && time-since >= 0.55 ? id : nil
    }
}

enum VocabularyIO {
    static func load(_ url: URL) throws -> Vocabulary {
        let values = try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 2_000_000 else { throw PoseError("The saved vocabulary is too large or unreadable.") }
        let library = try JSONDecoder().decode(Vocabulary.self,from:Data(contentsOf:url)); try library.validate(); return library
    }
    static func save(_ library: Vocabulary, to url: URL) throws {
        try library.validate()
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        var updated = library; updated.version = 2
        let data = try encoder.encode(updated)
        guard data.count <= 2_000_000 else { throw PoseError("This vocabulary is too large to save.") }
        // Preserve the original before the first intentional write in the newer format.
        if FileManager.default.fileExists(atPath:url.path) {
            let old = try load(url)
            if old.version == 1 {
                let backup = parent.appendingPathComponent("Vocabulary-v1-backup.json")
                if !FileManager.default.fileExists(atPath:backup.path) {
                    try FileManager.default.copyItem(at:url,to:backup)
                    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:backup.path)
                }
            }
        }
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
