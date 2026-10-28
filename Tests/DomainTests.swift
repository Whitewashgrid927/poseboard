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
        rejects("Unknown schema is rejected") { var value = library;value.version = 3;try value.validate() }
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
        expect(restored.review == nil && restored.composer.parts.first?.meaningID == custom.id,"Choosing a message only adds a draft fragment")
        restored.reviewPrompt()
        expect(restored.review?.text == custom.body,"Delivery requires an explicit review")
        store.beginTeaching()
        store.teaching?.text = "Conflicting meaning";store.teaching?.examples = [signature,signature,signature]
        let prior = store.vocabulary
        store.saveTeaching()
        expect(store.teaching != nil && store.error != nil && store.vocabulary == prior,"Conflicting teaching preserves the existing library")
        let invalidURL = temp.appendingPathComponent("corrupted-store.json")
        try Data("broken".utf8).write(to:invalidURL)
        let blocked = PoseStore(storage:invalidURL,observeSystem:false)
        expect(blocked.storageBlocked,"Corruption makes vocabulary changes read-only")
        blocked.remove(a)
        let retained = try Data(contentsOf:invalidURL)
        expect(String(data:retained,encoding:.utf8) == "broken","Even deletion cannot overwrite a corrupt saved library")
        try composerChecks(a:a,b:b,signature:signature,temp:temp)
        print("\(checks-failures)/\(checks) checks passed")
        if failures > 0 { exit(1) }
    }
    static func composerChecks(a: Meaning,b: Meaning,signature: PoseSignature,temp: URL) throws {
        var instruction = a
        instruction.prompt = "Examine this idea.\n\nKeep these words exactly as written."
        instruction.role = .instruction
        var modifier = b
        modifier.prompt = "Give alternatives and explain the tradeoffs."
        modifier.role = .modifier
        var composer = PromptComposer()
        try composer.add(instruction); try composer.add(modifier)
        expect(composer.text == instruction.body+"\n\n"+modifier.body,"Composition preserves order and verbatim paragraphs")
        expect(composer.parts.map(\.meaningID) == [a.id,b.id],"Prompt parts retain source identities")
        expect(composer.depth == .original,"Depth defaults to preserving saved text")
        try composer.setDepth(.detailed)
        expect(composer.text.hasSuffix(PromptDepth.detailed.instruction!),"Depth adds an explicit visible instruction")
        try composer.setContext("A selected passage.")
        expect(composer.text.hasSuffix("Context supplied for this prompt:\nA selected passage."),"Only supplied context is included")
        let full = composer
        rejects("Context size limit preserves the draft") { try composer.setContext(String(repeating:"x",count:8_001)) }
        expect(composer == full,"Failed context edit is atomic")
        try composer.edit("My revised draft\nwith another paragraph.")
        expect(composer.isEdited && composer.text == "My revised draft\nwith another paragraph.","Manual edits remain exact")
        rejects("Signs cannot overwrite manual edits") { try composer.add(a) }
        rejects("Depth cannot overwrite manual edits") { try composer.setDepth(.concise) }
        let edited = composer; composer.undo()
        expect(composer == edited,"Undo cannot silently discard manual edits")
        composer.useSigns()
        expect(composer.text == full.text,"Returning to signs restores the saved composition")
        composer.undo()
        expect(composer.parts.count == 1 && composer.parts.first?.meaningID == a.id,"Undo removes the last sign only")
        composer.clear()
        expect(composer.isEmpty && composer.context.isEmpty && composer.parts.isEmpty,"Clear removes prompt and context")
        for _ in 0..<12 { try composer.add(a) }
        rejects("Composition is bounded to twelve signs") { try composer.add(a) }
        var large = PromptComposer(), long = a
        long.prompt = String(repeating:"x",count:8_000)
        try large.add(long); try large.add(long)
        let before = large
        rejects("Composition total size is bounded") { try large.add(long) }
        expect(large == before,"Oversized append preserves existing text")
        rejects("Prompt control characters are rejected") { try PromptText.validate("Text\u{1B}[2J") }
        rejects("Empty prompt is rejected") { try PromptText.validate(" \n\t") }
        try PromptText.validate("Paragraph one.\n\nParagraph two.\tIndented.")
        expect(true,"Paragraphs and tabs are accepted as plain text")

        var latch = SignLatch()
        expect(latch.accept(a.id) == a.id,"First stable sign can be added")
        expect((0..<100).allSatisfy { _ in latch.accept(a.id) == nil },"Holding a sign cannot repeat it")
        for i in 0..<10 {
            let time = 1+Double(i)*0.07
            latch.observe(.init(time:time,hands:[hand(x:0.3)],detectedCount:1),now:time)
        }
        expect(latch.needsRelease,"One lost hand does not rearm the latch")
        for i in 0..<10 {
            let time = 2+Double(i)*0.07
            latch.observe(.init(time:time),now:time+1)
        }
        expect(latch.needsRelease,"Stale empty frames cannot rearm the latch")
        for i in 0..<10 {
            let time = 3+Double(i)*0.07
            latch.observe(.init(time:time,hands:[hand(x:0.3),hand(x:0.7)],detectedCount:3),now:time)
        }
        expect(latch.needsRelease,"Extra-hand frames cannot rearm the latch")
        latch.observe(.init(time:4),now:4)
        latch.observe(.init(time:5),now:5)
        expect(latch.needsRelease,"A gap between empty frames cannot count as a release hold")
        for i in 1..<9 { let time = 5+Double(i)*0.07; latch.observe(.init(time:time),now:time) }
        expect(!latch.needsRelease && latch.accept(b.id) == b.id,"Continuous fresh zero-hand frames rearm the next sign")
        for _ in 0..<20 { latch.observe(.init(time:6),now:6) }
        expect(latch.needsRelease,"Duplicate empty frames cannot accumulate a release")
        latch.reset(requiringRelease:true)
        expect(latch.accept(a.id) == nil,"Resuming review requires lowering both hands")

        let legacyURL = temp.appendingPathComponent("legacy/Vocabulary.json")
        try FileManager.default.createDirectory(at:legacyURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        let legacy = Vocabulary(version:1,meanings:[a,b])
        let legacyBytes = try JSONEncoder().encode(legacy)
        try legacyBytes.write(to:legacyURL)
        let loaded = try VocabularyIO.load(legacyURL)
        expect(loaded.meanings == [a,b] && loaded.meanings[0].body == a.text,"Old labels and hand examples load unchanged")
        let untouched = try Data(contentsOf:legacyURL)
        expect(untouched == legacyBytes,"Reading old vocabulary does not migrate it on disk")
        try VocabularyIO.save(loaded,to:legacyURL)
        let backup = try Data(contentsOf:legacyURL.deletingLastPathComponent().appendingPathComponent("Vocabulary-v1-backup.json"))
        expect(backup == legacyBytes,"First newer-format write keeps an exact legacy backup")
        let migrated = try VocabularyIO.load(legacyURL)
        expect(migrated.version == 2 && migrated.meanings == legacy.meanings,"Migration preserves every existing sign")
        expect(Vocabulary.starter.meanings.isEmpty,"New users start with their own empty vocabulary")

        let store = PoseStore(storage:temp.appendingPathComponent("composer-store/Vocabulary.json"),observeSystem:false)
        store.choose(instruction); store.choose(modifier)
        expect(store.composer.parts.count == 2 && store.review == nil,"Choosing signs only builds a local draft")
        store.reviewPrompt(now:100)
        let review = store.review!
        store.clearPrompt(); store.choose(a); store.setDepth(.concise)
        expect(store.composer.text == review.text,"Mutations are blocked during confirmation")
        expect(store.confirmPrompt(id:UUID(),now:101) == nil && store.review != nil,"Wrong confirmation ID cannot consume the review")
        let confirmed = store.confirmPrompt(id:review.id,now:101)
        expect(confirmed?.0 == review.text && confirmed?.1 == .clipboard,"Explicit confirmation returns only the exact reviewed text")
        expect(store.confirmPrompt(id:review.id,now:102) == nil,"Confirmation cannot be replayed")
        store.reviewPrompt(now:200)
        let expired = store.review!
        expect(store.confirmPrompt(id:expired.id,now:291) == nil,"Expired confirmation cannot deliver")
        store.reviewPrompt(now:300)
        let canceled = store.review!
        store.cancelReview()
        expect(store.confirmPrompt(id:canceled.id,now:301) == nil,"Canceled review cannot deliver")
        let serviceID = UUID()
        expect(store.beginService(serviceID),"A native text service starts an explicit destination request")
        expect(!store.beginService(UUID()),"Concurrent service requests are rejected")
        store.reviewPrompt(now:400)
        let serviceReview = store.review!
        expect(serviceReview.destination == .service(serviceID),"Review is bound to the requesting service")
        store.endService()
        expect(store.confirmPrompt(id:serviceReview.id,now:401) == nil,"Ended destination cannot receive an old review")
        _ = store.beginService(UUID())
        var canceledDelivery = false
        store.finishService = { text in canceledDelivery = text == nil }
        store.reviewPrompt(now:450)
        store.cancelDelivery()
        expect(canceledDelivery && store.review == nil,"Cancel completes a pending service with no text")
        store.endService()
        store.detail = a
        expect(!store.beginService(UUID()),"A detail sheet cannot be interrupted by an insertion request")
        store.detail = nil; store.showPrivacy = true
        expect(!store.beginService(UUID()),"A privacy sheet cannot be interrupted by an insertion request")
        store.showPrivacy = false
        var changed = PromptComposer(); try changed.add(a)
        let snapshot = PromptReview(revision:changed.revision,text:changed.text,destination:.clipboard,createdAt:500)
        try changed.add(b)
        rejects("Changed draft invalidates its confirmation") { try snapshot.validate(composer:changed,destination:.clipboard,now:501) }
        var original = PromptComposer(); try original.add(a)
        let bound = PromptReview(revision:original.revision,text:original.text,destination:.service(UUID()),createdAt:600)
        rejects("Destination substitution invalidates confirmation") { try bound.validate(composer:original,destination:.clipboard,now:601) }

        store.beginTeaching(instruction,editText:true)
        store.teaching?.prompt = "Edited paragraphs\n\nWithout new training."
        store.saveTeaching()
        expect(store.vocabulary.meanings.first?.examples == instruction.examples,"Text edits preserve saved hand examples")
        expect(store.vocabulary.meanings.first?.body == "Edited paragraphs\n\nWithout new training.","Text edits support multiple paragraphs")
    }
}
