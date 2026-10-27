import Foundation

@main @MainActor struct DomainTests {
    static var checks = 0
    static var failures = 0
    static func expect(_ condition: @autoclosure () -> Bool,_ title: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(title)") }
    }
    static func rejects(_ title: String,_ work: () throws -> Void) {
        checks += 1
        do { try work(); failures += 1; print("FAIL: \(title)") } catch {}
    }
    static func hand(x: Double,y: Double = 0.35,scale: Double = 0.09,closed: Bool = false) -> ObservedHand {
        var p: [Vector] = [.init(x:0,y:0),.init(x:-0.35,y:0.25),.init(x:-0.65,y:0.5),.init(x:-0.85,y:0.75),.init(x:-1.05,y:0.95)]
        for (i,bx) in [-0.4,0.0,0.35,0.65].enumerated() {
            let length = [1.9,2.1,1.9,1.55][i]
            p += [.init(x:bx,y:0.75),.init(x:bx,y:closed ? 1.0 : 1.25),.init(x:bx+0.1,y:closed ? 0.65 : length-0.25),.init(x:bx+0.15,y:closed ? 0.35 : length)]
        }
        return .init(joints:p.map { .init(point:.init(x:x+$0.x*scale/(1280.0/720),y:y+$0.y*scale),confidence:0.95) })
    }
    static func frame(closed: Bool = false) -> PoseFrame { .init(time:1,hands:[hand(x:0.3),hand(x:0.7,closed:closed)],detectedCount:2) }
    static func main() throws {
        let base = frame(), signature = PoseSignature.make(base)!
        expect(signature.first.count == 21 && signature.second.count == 21,"Both hands are represented")
        var reordered = base; reordered.hands.reverse()
        expect(PoseSignature.make(reordered) == signature,"Vision result order does not swap hand identity")
        var translated = base
        for h in translated.hands.indices { for j in translated.hands[h].joints.indices { translated.hands[h].joints[j]?.point.x += 0.04; translated.hands[h].joints[j]?.point.y += 0.03 } }
        expect(PoseSignature.distance(signature,PoseSignature.make(translated)!) < 0.00001,"Whole-pose translation is invariant")
        var scaled = base
        for h in scaled.hands.indices { for j in scaled.hands[h].joints.indices { if let p = scaled.hands[h].joints[j]?.point { scaled.hands[h].joints[j]?.point = .init(x:0.5+(p.x-0.5)*0.8,y:0.5+(p.y-0.5)*0.8) } } }
        expect(PoseSignature.distance(signature,PoseSignature.make(scaled)!) < 0.00001,"Camera-distance scaling is invariant")
        let changed = PoseSignature.make(frame(closed:true))!
        expect(PoseSignature.distance(signature,changed) > 0.23,"Changing fingers on only one hand changes the pair")
        var separated = base; separated.hands[1] = hand(x:0.85)
        expect(PoseSignature.distance(signature,PoseSignature.make(separated)!) > 0.20,"Relative hand spacing contributes to the meaning")
        var one = base; one.hands.removeLast();one.detectedCount = 1
        expect(PoseSignature.make(one) == nil,"One hand cannot become a two-hand pose")
        var third = base; third.detectedCount = 3
        expect(PoseSignature.make(third) == nil,"Extra raw hand observations reject the whole pose")
        var overlap = base; overlap.hands[1] = hand(x:0.301)
        expect(PoseSignature.make(overlap) == nil,"Overlapping hands do not get arbitrarily assigned")
        var low = base; low.hands[0].joints[0]?.confidence = 0.2
        expect(PoseSignature.make(low) == nil,"Low-confidence wrist rejects recognition")
        var missing = base
        for i in 1...7 { missing.hands[0].joints[i] = nil }
        expect(PoseSignature.make(missing) == nil,"Occluded fingers are not guessed")
        var invalid = base; invalid.hands[0].joints[0]?.point.x = .nan
        expect(PoseSignature.make(invalid) == nil,"Nonfinite geometry rejects recognition")
        invalid = base;invalid.width = .infinity
        expect(PoseSignature.make(invalid) == nil,"Invalid frame dimensions are rejected")
        let a = Meaning(text:"First",symbol:.yes,examples:[signature,signature,signature])
        let b = Meaning(text:"Second",symbol:.pause,examples:[changed,changed,changed])
        let library = Vocabulary(meanings:[a,b])
        expect(library.match(signature) == a.id,"The taught pose matches its own meaning")
        expect(library.match(changed) == b.id,"The second meaning is distinct")
        expect(Vocabulary.starter.match(signature) == nil,"Starter meanings do not pretend to have learned poses")
        let duplicate = Meaning(text:"Duplicate",symbol:.no,examples:a.examples)
        expect(Vocabulary(meanings:[a,duplicate]).match(signature) == nil,"Ambiguous meanings produce no match")
        expect(library.conflict(with:duplicate)?.id == a.id,"Teaching detects a collision with an existing pose")
        expect(library.conflict(with:a) == nil,"Retraining the same meaning does not conflict with itself")
        var unsupported = signature; unsupported.first = Array(repeating:nil,count:21)
        expect(!PoseSignature.distance(signature,unsupported).isFinite,"Missing comparison landmarks cannot yield a good match")
        expect(PoseSignature.average([signature,signature]) == signature,"Stable training samples can be combined")
        expect(PoseSignature.average([]) == nil,"Empty examples do not produce a pose")
        var gate = StableMatch()
        expect(gate.update(a.id,time:1,now:1) == nil,"A single frame never confirms a meaning")
        var accepted: UUID?
        for index in 1...9 { let time = 1+Double(index)*0.07; accepted = gate.update(a.id,time:time,now:time) }
        expect(accepted == a.id,"Consistent fresh frames confirm a meaning")
        expect(gate.update(nil,time:1.7,now:1.7) == nil,"Tracking loss clears temporal recognition")
        expect(gate.update(a.id,time:1.8,now:1.8) == nil,"Tracking recovery must hold again")
        expect(gate.update(a.id,time:2,now:3) == nil,"Stale frames cannot confirm a meaning")
        gate = .init()
        for index in 0...20 { _ = gate.update(index%2 == 0 ? a.id : b.id,time:4+Double(index)*0.07,now:4+Double(index)*0.07) }
        expect(gate.update(a.id,time:5.5,now:5.5) == nil,"Alternating poses cannot accumulate a hold")
        gate = .init()
        for _ in 0...15 { accepted = gate.update(a.id,time:6,now:6) }
        expect(accepted == nil,"Duplicate timestamps cannot accumulate evidence")
        rejects("Malformed landmark arrays reject persistence") { var item = a;item.examples[0].first = [];try item.validate() }
        rejects("Unknown schema is rejected") { var value = library;value.version = 2;try value.validate() }
        rejects("Duplicate IDs are rejected") { try Vocabulary(meanings:[a,a]).validate() }
        rejects("Unbounded labels are rejected") { try Meaning(text:String(repeating:"a",count:101),symbol:.star).validate() }
        rejects("Control characters are rejected") { try Meaning(text:"bad\nlabel",symbol:.star).validate() }
        rejects("Nonfinite tolerance is rejected") { var item = a;item.tolerance = .nan;try item.validate() }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("poseboard-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        let file = temp.appendingPathComponent("Vocabulary.json")
        try VocabularyIO.save(library,to:file)
        let loaded = try VocabularyIO.load(file)
        expect(loaded == library,"Landmark-only vocabulary round-trips")
        let permissions = try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber
        expect(permissions?.intValue == 0o600,"Vocabulary file is private to the user")
        let saved = try Data(contentsOf:file)
        rejects("Invalid saves are rejected before replacing the file") { try VocabularyIO.save(.init(meanings:[a,a]),to:file) }
        let afterFailure = try Data(contentsOf:file)
        expect(afterFailure == saved,"Failed validation preserves previous data")
        try Data("corrupted".utf8).write(to:file)
        rejects("Corrupt files do not silently become an empty library") { _ = try VocabularyIO.load(file) }
        try Data(repeating:0,count:2_000_001).write(to:file)
        rejects("Oversized library is rejected before decoding") { _ = try VocabularyIO.load(file) }
        let storeURL = temp.appendingPathComponent("store/Vocabulary.json")
        let store = PoseStore(storage:storeURL,observeSystem:false)
        expect(store.cameraState == .off && store.teaching == nil,"App initialization never starts the camera")
        store.beginTeaching()
        store.teaching?.text = "My custom meaning";store.teaching?.examples = [signature,signature,signature]
        store.saveTeaching()
        expect(store.teaching == nil && store.vocabulary.meanings.last?.learned == true,"Three examples save a custom meaning")
        let restored = PoseStore(storage:storeURL,observeSystem:false)
        expect(restored.vocabulary == store.vocabulary,"A fresh session restores taught meanings")
        let custom = restored.vocabulary.meanings.last!
        restored.choose(custom)
        expect(restored.presenting == nil && restored.draft?.id == custom.id,"Choosing a message does not display it")
        restored.showMessage()
        expect(restored.presenting?.id == custom.id,"Showing a message requires the explicit action")
        store.beginTeaching()
        store.teaching?.text = "Conflicting meaning";store.teaching?.examples = [signature,signature,signature]
        let prior = store.vocabulary
        store.saveTeaching()
        expect(store.teaching != nil && store.error != nil && store.vocabulary == prior,"Conflicting teaching preserves the existing library")
        let invalidURL = temp.appendingPathComponent("corrupted-store.json")
        try Data("broken".utf8).write(to:invalidURL)
        let blocked = PoseStore(storage:invalidURL,observeSystem:false)
        expect(blocked.storageBlocked,"Corruption makes vocabulary changes read-only")
        blocked.remove(blocked.vocabulary.meanings[0])
        let retained = try Data(contentsOf:invalidURL)
        expect(String(data:retained,encoding:.utf8) == "broken","Even deletion cannot overwrite a corrupt saved library")
        print("\(checks-failures)/\(checks) checks passed")
        if failures > 0 { exit(1) }
    }
}
