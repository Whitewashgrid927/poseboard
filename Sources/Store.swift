import AppKit
import Combine
@preconcurrency import AVFoundation

struct Teaching: Identifiable {
    var id = UUID()
    var editingID: UUID?
    var text = ""
    var prompt = ""
    var role = PromptRole.instruction
    var editingText = false
    var symbol: MeaningSymbol = .greeting
    var examples: [PoseSignature] = []
    var capturing = false
    var readyAt = 0.0
    var deadline = 0.0
    var samples: [PoseSignature] = []
    var sampleStart = 0.0
    var lastSampleTime = 0.0
    var instruction = "Choose a meaning, then show both hands."
    var progress = 0.0
    var finished: Bool { examples.count == 3 }
}

struct ContextEditing: Identifiable {
    let id = UUID()
    let card: PromptContext?
}

@MainActor final class PoseStore: ObservableObject {
    @Published private(set) var vocabulary = Vocabulary.starter
    @Published private(set) var cameraState: CameraState = .off
    @Published private(set) var frame = PoseFrame()
    @Published private(set) var trackingText = "Camera off"
    @Published private(set) var currentMatch: UUID?
    @Published var teaching: Teaching?
    @Published var detail: Meaning?
    @Published var error: String?
    @Published var notice: String?
    @Published var showPrivacy = false
    @Published var cameraID: String?
    @Published private(set) var composer = PromptComposer()
    @Published private(set) var review: PromptReview?
    @Published private(set) var needsRelease = false
    @Published var floating = false
    @Published var editingDraft = false
    @Published var contextEditor: ContextEditing?
    @Published var showInsertionHelp = false
    @Published private(set) var serviceID: UUID?
    var finishService: ((String?) -> Void)?
    private var generation = UUID()
    private var wanted = false
    private var recognizer = StableMatch()
    private var signLatch = SignLatch()
    private var timer: Timer?
    private var tokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private(set) var storageBlocked = false
    let libraryURL: URL
    lazy var camera = PoseCamera(onFrame:{ [weak self] token, frame in
        Task { @MainActor [weak self] in self?.receive(frame,token:token) }
    },onState:{ [weak self] token, state in
        Task { @MainActor [weak self] in self?.receive(state,token:token) }
    })
    var running: Bool { cameraState == .running }
    var trainedCount: Int { vocabulary.meanings.filter(\.learned).count }
    init(storage: URL? = nil, observeSystem: Bool = true) {
        libraryURL = storage ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Poseboard/Vocabulary.json")
        if FileManager.default.fileExists(atPath:libraryURL.path) {
            do { vocabulary = try VocabularyIO.load(libraryURL) }
            catch { storageBlocked = true; self.error = "Your saved vocabulary could not be opened. It has been preserved. Restart after restoring the file; teaching is disabled until it loads correctly." }
        }
        guard observeSystem else { return }
        let timer = Timer(timeInterval:0.15,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(timer,forMode:.common)
        RunLoop.main.add(timer,forMode:.modalPanel)
        self.timer = timer
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.sessionDidResignActiveNotification] {
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.cancelDelivery(); self?.stopCamera(message:"Camera paused. Start it when you are ready.") }
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cancelDelivery()
                if self.wanted && !self.floating { self.stopCamera(message:"Camera paused while Poseboard is in the background.") }
            }
        })
        for name in [AVCaptureSession.runtimeErrorNotification,AVCaptureSession.wasInterruptedNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] notification in
                guard notification.object is AVCaptureSession else { return }
                Task { @MainActor in self?.stopCamera(message:"Camera interrupted. Start it again when ready.") }
            })
        }
    }
    func startCamera() {
        guard !wanted else { return }
        wanted = true; generation = UUID(); let token = generation
        resetRecognition(requiringRelease:!composer.isEmpty)
        cameraState = .starting; notice = nil
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: camera.start(deviceID:cameraID,generation:token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.wanted, self.generation == token else { return }
                    if granted { self.camera.start(deviceID:self.cameraID,generation:token) }
                    else { self.wanted = false; self.cameraState = .failed("Camera permission was not granted. You can still choose messages from your vocabulary.") }
                }
            }
        default: wanted = false; cameraState = .failed("Enable Poseboard in System Settings → Privacy & Security → Camera, then try again.")
        }
    }
    func stopCamera(message: String? = nil) {
        wanted = false; generation = UUID(); camera.stop(); cameraState = .off; frame = .init()
        trackingText = "Camera off"; resetRecognition(requiringRelease:!composer.isEmpty)
        cancelCapture()
        if let message { notice = message }
    }
    func changeCamera(_ id: String?) { stopCamera(); cameraID = id; startCamera() }
    private func receive(_ state: CameraState,token: UUID) {
        guard token == generation, wanted else { return }
        cameraState = state
        if case .failed = state { wanted = false; resetRecognition(requiringRelease:!composer.isEmpty); frame = .init(); cancelCapture() }
    }
    private func receive(_ next: PoseFrame,token: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        guard token == generation, wanted, running, now-next.time >= 0, now-next.time <= 0.30, next.time > frame.time else { return }
        frame = next
        let signature = PoseSignature.make(next)
        if next.detectedCount > 2 { trackingText = "Keep only your two hands in view" }
        else if next.detectedCount < 2 { trackingText = "Show both hands" }
        else if signature == nil { trackingText = "Separate your hands and keep your fingers visible" }
        else { trackingText = "Both hands visible" }
        if teaching != nil { currentMatch = nil; recognizer.reset(); train(signature,time:next.time); return }
        guard detail == nil, review == nil, !editingDraft, contextEditor == nil, !showPrivacy, !showInsertionHelp else {
            resetRecognition(requiringRelease:true); return
        }
        signLatch.observe(next,now:now)
        let match = signature.flatMap { vocabulary.match($0) }
        currentMatch = recognizer.update(match,time:next.time,now:now)
        if !composer.isEdited, let accepted = signLatch.accept(currentMatch), let meaning = vocabulary.meanings.first(where:{$0.id == accepted}) {
            appendMeaning(meaning)
        }
        needsRelease = signLatch.needsRelease
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if running, now-frame.time > 0.45 {
            frame = .init(); currentMatch = nil; recognizer.reset(); trackingText = "Waiting for camera frames"
            if teaching?.capturing == true { teaching?.samples = []; teaching?.sampleStart = 0; teaching?.progress = 0 }
        }
        if let review, now-review.createdAt >= 90 { cancelDelivery(); notice = "Confirmation expired. Your draft is still here." }
        if running, !NSApp.windows.contains(where:{ $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }) {
            stopCamera(message:"Camera paused while the window is hidden.")
        }
        guard let session = teaching, session.capturing else { return }
        if now < session.readyAt { teaching?.instruction = "Get ready · \(max(1,Int(ceil(session.readyAt-now))))" }
        if now > session.deadline {
            cancelCapture(); teaching?.instruction = "No steady example captured. Keep both hands visible and try again."
        }
    }
    func beginTeaching(_ meaning: Meaning? = nil, editText: Bool = false) {
        guard review == nil, teaching == nil, contextEditor == nil, !editingDraft, !showInsertionHelp else { return }
        guard !storageBlocked else { error = "Your existing vocabulary needs to be restored before teaching can save changes."; return }
        guard meaning != nil || vocabulary.meanings.count < 100 else { error = "Your vocabulary can contain up to 100 meanings."; return }
        detail = nil; resetRecognition(requiringRelease:true)
        teaching = .init(editingID:meaning?.id,text:meaning?.text ?? "",prompt:meaning?.body ?? "",role:meaning?.promptRole ?? .instruction,
                         editingText:editText,symbol:meaning?.symbol ?? .star,examples:editText ? meaning?.examples ?? [] : [])
    }
    func captureExample() {
        guard running, let session = teaching, !session.finished, !session.capturing,
              !session.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        teaching?.capturing = true; teaching?.samples = []; teaching?.sampleStart = 0; teaching?.progress = 0
        teaching?.readyAt = now+2.5; teaching?.deadline = now+25
        teaching?.instruction = "Get ready · 3"
    }
    func cancelCapture() {
        guard teaching?.capturing == true else { return }
        teaching?.capturing = false; teaching?.samples = []; teaching?.sampleStart = 0; teaching?.progress = 0
        teaching?.instruction = "Capture paused. Your completed examples are kept."
    }
    func restartTeaching() { cancelCapture(); teaching?.examples = []; teaching?.instruction = "Start again with one comfortable, repeatable pose." }
    private func train(_ signature: PoseSignature?,time: Double) {
        guard var session = teaching, session.capturing, time >= session.readyAt else { return }
        guard let signature else {
            session.samples = []; session.sampleStart = 0; session.progress = 0; session.instruction = trackingText; teaching = session; return
        }
        if let anchor = session.samples.first, time-session.lastSampleTime > 0.25 || PoseSignature.distance(anchor,signature) > 0.13 {
            session.samples = []; session.sampleStart = 0; session.progress = 0
        }
        if session.samples.isEmpty { session.sampleStart = time }
        session.lastSampleTime = time
        session.samples.append(signature)
        session.instruction = "Hold this pose steady"
        session.progress = min(1,(time-session.sampleStart)/0.85)
        guard session.samples.count >= 10, time-session.sampleStart >= 0.85 else { teaching = session; return }
        guard let average = PoseSignature.average(session.samples) else {
            session.samples = []; session.sampleStart = 0; session.progress = 0; session.instruction = "Keep both hands and fingertips in view."; teaching = session; return
        }
        if let first = session.examples.first, PoseSignature.distance(first,average) > 0.26 {
            session.capturing = false; session.samples = []; session.progress = 0
            session.instruction = "This differs from your first example. Try the same hand shapes and spacing again."; teaching = session; return
        }
        session.examples.append(average); session.capturing = false; session.samples = []; session.progress = 1
        session.instruction = session.finished ? "Three examples captured. Save your pose, then try it in the camera." : "Example saved. Relax your hands, then capture the same pose again."
        teaching = session
    }
    func saveTeaching(withoutSign: Bool = false) {
        guard let session = teaching, !session.capturing, session.finished || session.editingText || (withoutSign && session.examples.isEmpty), !storageBlocked else { return }
        let spread = session.examples.flatMap { a in session.examples.map { PoseSignature.distance(a,$0) } }.max() ?? 0
        var meaning = Meaning(id:session.editingID ?? UUID(),text:session.text.trimmingCharacters(in:.whitespacesAndNewlines),symbol:session.symbol,examples:session.examples)
        meaning.tolerance = min(0.23,max(0.13,0.10+spread*0.65))
        meaning.prompt = session.prompt.isEmpty ? session.text : session.prompt
        meaning.role = session.role
        if session.editingText, let old = vocabulary.meanings.first(where:{$0.id == session.editingID}) { meaning.tolerance = old.tolerance }
        if let conflict = vocabulary.conflict(with:meaning) { error = "This looks too similar to “\(conflict.text)”. Give the new meaning a different hand shape or spacing, then capture it again."; return }
        var updated = vocabulary; updated.version = 2
        if let index = updated.meanings.firstIndex(where:{$0.id == meaning.id}) { updated.meanings[index] = meaning }
        else { updated.meanings.append(meaning) }
        guard persist(updated) else { return }
        teaching = nil; resetRecognition(requiringRelease:true)
        notice = meaning.learned ? "Sign saved on this Mac. Lower your hands, then try it." : "Phrase saved. You can add it by clicking, or teach its sign."
    }
    @discardableResult private func persist(_ updated: Vocabulary) -> Bool {
        guard !storageBlocked else { error = "Your saved vocabulary could not be loaded. It is preserved; changes are disabled until it is restored."; return false }
        do { try VocabularyIO.save(updated,to:libraryURL); vocabulary = updated; return true }
        catch { self.error = "Could not save your vocabulary. Your current entries are unchanged. \(error.localizedDescription)"; return false }
    }
    func choose(_ meaning: Meaning) {
        guard review == nil else { return }
        resetRecognition(requiringRelease:true); detail = nil
        appendMeaning(meaning)
    }
    func remove(_ meaning: Meaning) {
        var updated = vocabulary; updated.meanings.removeAll { $0.id == meaning.id }
        if persist(updated) { detail = nil; resetRecognition(requiringRelease:true) }
    }
    private func resetRecognition(requiringRelease: Bool = false) {
        recognizer.reset(); currentMatch = nil; signLatch.reset(requiringRelease:requiringRelease); needsRelease = requiringRelease
    }
    private func appendMeaning(_ meaning: Meaning) {
        do { try composer.add(meaning); notice = "Added “\(meaning.text)”. Lower your hands before the next sign." }
        catch { notice = error.localizedDescription }
    }
    func setDepth(_ depth: PromptDepth) {
        guard review == nil else { return }
        do { try composer.setDepth(depth) } catch { self.error = error.localizedDescription }
    }
    func beginContext(_ card: PromptContext? = nil) {
        guard review == nil, teaching == nil, detail == nil, contextEditor == nil, !editingDraft, !showPrivacy, !showInsertionHelp, !composer.isEdited else { return }
        guard card != nil || composer.contexts.count < PromptContext.maximumCards else { return }
        resetRecognition(requiringRelease:true)
        contextEditor = .init(card:card)
    }
    func saveContext(title: String,body: String) {
        guard review == nil, let session = contextEditor else { return }
        do {
            let title = title.trimmingCharacters(in:.whitespacesAndNewlines)
            if let card = session.card { try composer.updateContext(id:card.id,title:title,body:body) }
            else { try composer.addContext(.init(title:title,body:body)) }
            contextEditor = nil; resetRecognition(requiringRelease:true)
            notice = "Context saved in this draft only. Review the full prompt before insertion."
        }
        catch { self.error = error.localizedDescription }
    }
    func includeContext(_ card: PromptContext,included: Bool) {
        guard review == nil, contextEditor == nil else { return }
        do {
            try composer.setContextIncluded(id:card.id,included:included)
            resetRecognition(requiringRelease:true)
            notice = included ? "“\(card.title)” is included in the prompt." : "“\(card.title)” is kept here but excluded from the prompt."
        }
        catch { self.error = error.localizedDescription }
    }
    func removeContext(_ card: PromptContext) {
        guard review == nil, contextEditor == nil else { return }
        do { try composer.removeContext(id:card.id); resetRecognition(requiringRelease:true); notice = "Context card removed from this draft." }
        catch { self.error = error.localizedDescription }
    }
    func editPrompt(_ text: String) {
        guard review == nil else { return }
        do { try composer.edit(text); editingDraft = false; resetRecognition(requiringRelease:true) }
        catch { self.error = error.localizedDescription }
    }
    func useSigns() { guard review == nil else { return }; composer.useSigns(); resetRecognition(requiringRelease:true) }
    func undoSign() { guard review == nil else { return }; composer.undo(); resetRecognition(requiringRelease:true) }
    func clearPrompt() { guard review == nil else { return }; composer.clear(); resetRecognition(requiringRelease:true) }
    var deliveryDestination: DeliveryDestination { serviceID.map(DeliveryDestination.service) ?? .clipboard }
    func reviewPrompt(now: Double = ProcessInfo.processInfo.systemUptime) {
        guard !composer.isEmpty, teaching == nil, !editingDraft, contextEditor == nil, !showPrivacy, !showInsertionHelp, detail == nil, review == nil else { return }
        do { try PromptText.validate(composer.text) } catch { self.error = error.localizedDescription; return }
        resetRecognition(requiringRelease:true)
        review = .init(revision:composer.revision,text:composer.text,destination:deliveryDestination,createdAt:now)
    }
    /// Consume the exact reviewed snapshot once. Callers perform only the chosen local delivery.
    func confirmPrompt(id: UUID, now: Double = ProcessInfo.processInfo.systemUptime) -> (String,DeliveryDestination)? {
        guard let review, review.id == id else { return nil }
        defer { self.review = nil; resetRecognition(requiringRelease:true) }
        do { try review.validate(composer:composer,destination:deliveryDestination,now:now) }
        catch { self.error = error.localizedDescription; return nil }
        return (review.text,review.destination)
    }
    func cancelReview() { review = nil; resetRecognition(requiringRelease:true) }
    func beginService(_ id: UUID) -> Bool {
        guard serviceID == nil, teaching == nil, detail == nil, review == nil, !editingDraft, contextEditor == nil, !showPrivacy, !showInsertionHelp else { return false }
        serviceID = id; notice = nil; resetRecognition(requiringRelease:true); return true
    }
    func endService() { serviceID = nil; finishService = nil; cancelReview() }
    func cancelDelivery() { cancelReview(); finishService?(nil) }
}
