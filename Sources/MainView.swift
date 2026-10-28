import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var store: PoseStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = true
    @State private var vocabularyHeight: CGFloat = 170
    @State private var dragStart: CGFloat?
    @State private var query = ""
    @State private var showInsertionHelp = false
    @State private var clearConfirmation = false
    var body: some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.89,green:0.93,blue:0.99),Color(red:0.97,green:0.93,blue:0.94),Color(red:0.85,green:0.91,blue:0.98)],startPoint:.topLeading,endPoint:.bottomTrailing)
            VStack(spacing:16) {
                toolbar
                HStack(spacing:24) {
                    VStack(alignment:.leading,spacing:9) {
                        Text("Your hands. Your words.").font(.system(size:27,weight:.medium,design:.rounded))
                        Text(store.running ? store.trackingText : "Teach signs. Combine them into a prompt.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(store.running && store.needsRelease ? "Lower both hands before the next sign." : "Your instructions stay exactly as you wrote them.")
                            .font(.caption).foregroundStyle(store.needsRelease && store.running ? .indigo : .secondary)
                    }
                    Spacer()
                    cameraTile.frame(width:220,height:120)
                }.padding(.horizontal,10)
                composerPanel
            }.padding(.horizontal,28).padding(.bottom,24).padding(.top,12)
        }
        .frame(minWidth:880,minHeight:740)
        .preferredColorScheme(.light)
        .background(WindowPresentation(floating:store.floating))
        .sheet(isPresented:Binding(get:{store.teaching != nil},set:{if !$0 { store.cancelCapture(); store.teaching = nil }})) { TeachView(store:store) }
        .sheet(item:$store.detail) { MeaningView(store:store,meaning:$0) }
        .sheet(item:Binding(get:{store.review},set:{if $0 == nil { store.cancelReview() }})) { ReviewView(store:store,review:$0) }
        .sheet(isPresented:$store.editingDraft) {
            PromptEditor(title:"Edit your prompt",subtitle:"Editing pauses sign additions. Your changes stay in this draft.",initial:store.composer.text,limit:PromptText.limit) { store.editPrompt($0) }
        }
        .sheet(isPresented:$store.editingContext) {
            PromptEditor(title:"Context for this prompt",subtitle:"Paste text you choose to include. Context stays in memory until you clear or quit.",initial:store.composer.context,limit:8_000,allowsEmpty:true) { store.setContext($0) }
        }
        .sheet(isPresented:$store.showPrivacy) { PrivacyView() }
        .sheet(isPresented:$showInsertionHelp) { InsertionHelp() }
        .alert("Poseboard",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) { Button("OK",role:.cancel) { store.error = nil } } message:{ Text(store.error ?? "") }
        .confirmationDialog("Clear this prompt and its context?",isPresented:$clearConfirmation,titleVisibility:.visible) {
            Button("Clear prompt",role:.destructive) { store.clearPrompt() }
        }
        .onDisappear { store.cancelDelivery(); store.stopCamera() }
    }
    private var toolbar: some View {
        HStack(spacing:12) {
            Text("Poseboard").font(.headline).padding(.leading,58)
            Spacer()
            Label("On device",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
            Button { store.floating.toggle() } label: { Label(store.floating ? "Floating" : "Float",systemImage:store.floating ? "pin.fill" : "pin") }
                .buttonStyle(.glass).tint(store.floating ? .indigo : nil)
                .help("Keep this window above other apps. If the camera is on, tracking continues while this window stays visible.")
            Menu {
                Button(store.running ? "Stop camera" : "Start camera") { store.running ? store.stopCamera() : store.startCamera() }
                Divider()
                Button("Default camera") { store.changeCamera(nil) }
                ForEach(PoseCamera.devices()) { device in Button(device.name) { store.changeCamera(device.id) } }
            } label: { Image(systemName:store.running ? "video.fill" : "video.slash") }
                .menuStyle(.borderlessButton).fixedSize().padding(8).glassEffect(.regular,in:.capsule).accessibilityLabel("Camera controls")
            Button { store.showPrivacy = true } label: { Image(systemName:"info.circle") }.buttonStyle(.glass).accessibilityLabel("Privacy and help")
        }.frame(height:32)
    }
    private var cameraTile: some View {
        ZStack {
            if store.running {
                CameraPreview(camera:store.camera)
                Landmarks(frame:store.frame)
                VStack { Spacer(); HStack(spacing:5) {
                    Circle().fill(.green).frame(width:5,height:5)
                    Text(store.floating ? "Camera live · floating" : "Camera live").font(.system(size:10))
                }.padding(6).glassEffect(.regular,in:.capsule).padding(7) }
            } else {
                VStack(spacing:12) {
                    Image(systemName:"hands.sparkles").font(.system(size:25,weight:.light)).foregroundStyle(.indigo)
                    if store.cameraState == .starting { ProgressView().controlSize(.small) }
                    else { Button("Start camera") { store.startCamera() }.buttonStyle(.glass) }
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black.opacity(store.running ? 1 : 0.025))
            .clipShape(RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.65)))
    }
    private var composerPanel: some View {
        GlassEffectContainer(spacing:12) {
            VStack(spacing:14) {
                handle
                HStack {
                    Text("Compose a prompt").font(.headline)
                    Spacer()
                    if store.serviceID != nil {
                        Label("Insertion requested",systemImage:"text.cursor").font(.caption).foregroundStyle(.indigo)
                        Button("Cancel insertion") { store.cancelDelivery() }.buttonStyle(.borderless)
                    } else {
                        Button("Connect to a text field") { showInsertionHelp = true }.buttonStyle(.borderless).font(.caption)
                    }
                }
                signChips
                HStack {
                    Text(store.composer.isEdited ? "Your edited prompt" : "Your prompt").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if store.composer.isEdited {
                        Button("Use signs") { store.useSigns() }.font(.caption).buttonStyle(.borderless)
                    }
                    Button("Edit") { store.editingDraft = true }.font(.caption).buttonStyle(.borderless).disabled(store.composer.isEmpty)
                }
                ScrollView {
                    Text(store.composer.isEmpty ? "Your prompt appears here as you add signs or choose phrases from your vocabulary." : store.composer.text)
                        .font(.system(size:16)).foregroundStyle(store.composer.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(14)
                }.frame(minHeight:82,maxHeight:140).background(.white.opacity(0.32),in:RoundedRectangle(cornerRadius:17))
                    .accessibilityLabel("Prompt preview")
                HStack(spacing:12) {
                    Text("Depth").font(.caption).foregroundStyle(.secondary)
                    Picker("Depth",selection:Binding(get:{store.composer.depth},set:{ store.setDepth($0) })) {
                        ForEach(PromptDepth.allCases,id:\.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth:410).labelsHidden().disabled(store.composer.isEdited)
                    Spacer(minLength:8)
                    Button { store.editingContext = true } label: {
                        Label(store.composer.context.isEmpty ? "Add context" : "Context added",systemImage:"text.quote")
                    }.buttonStyle(.glass).disabled(store.composer.isEdited)
                }
                HStack(spacing:14) {
                    Button { store.undoSign() } label: { Label("Undo",systemImage:"arrow.uturn.backward") }
                        .buttonStyle(.borderless).disabled(store.composer.parts.isEmpty || store.composer.isEdited)
                    Button("Clear") { clearConfirmation = true }.buttonStyle(.borderless).disabled(store.composer.isEmpty)
                    Spacer()
                    Text(store.serviceID == nil ? "Review before copying" : "Inserts a draft · never sends")
                        .font(.system(size:11)).foregroundStyle(.secondary)
                    Button(store.serviceID == nil ? "Review & copy" : "Review & insert") { store.reviewPrompt() }
                        .buttonStyle(.glassProminent).tint(.indigo).disabled(store.composer.isEmpty)
                }
                if let notice = store.notice {
                    Text(notice).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                }
                if case .failed(let message) = store.cameraState {
                    Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                }
                if expanded { vocabulary }
            }.padding(.horizontal,24).padding(.bottom,22)
                .glassEffect(.regular,in:.rect(cornerRadius:30))
                .shadow(color:.black.opacity(0.10),radius:22,y:12)
        }
    }
    private var handle: some View {
        Capsule().fill(.secondary.opacity(0.35)).frame(width:42,height:4)
            .frame(maxWidth:.infinity).frame(height:19).contentShape(Rectangle())
            .onTapGesture { toggleVocabulary() }
            .gesture(DragGesture().onChanged { value in
                if dragStart == nil { dragStart = expanded ? vocabularyHeight : 0 }
                let height = (dragStart ?? 0)-value.translation.height
                expanded = height > 70; vocabularyHeight = min(230,max(120,height))
            }.onEnded { _ in dragStart = nil })
            .accessibilityElement().accessibilityLabel(expanded ? "Collapse vocabulary" : "Expand vocabulary")
            .accessibilityAddTraits(.isButton).accessibilityAction { toggleVocabulary() }
    }
    private func toggleVocabulary() {
        withAnimation(reduceMotion ? nil : .spring(response:0.35,dampingFraction:0.88)) { expanded.toggle() }
    }
    private var signChips: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:9) {
                if store.composer.parts.isEmpty {
                    Label("Make a sign or choose a phrase",systemImage:"hand.raised").font(.callout).foregroundStyle(.secondary).padding(12)
                }
                ForEach(store.composer.parts) { part in
                    Label(part.name,systemImage:part.symbol.rawValue).font(.system(size:13,weight:.medium)).lineLimit(1)
                        .padding(.horizontal,15).padding(.vertical,12)
                        .glassEffect(.regular.tint(part.role == .instruction ? .indigo.opacity(0.18) : .clear),in:.capsule)
                }
            }.padding(2)
        }.frame(height:48)
    }
    private var vocabulary: some View {
        VStack(spacing:10) {
            Divider().opacity(0.4)
            HStack {
                Text("Your vocabulary").font(.system(size:14,weight:.semibold))
                Text("\(store.trainedCount) signs").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.vocabulary.meanings.count > 6 { TextField("Search",text:$query).textFieldStyle(.roundedBorder).frame(width:120) }
                Button { store.beginTeaching() } label: { Label("Teach a sign",systemImage:"plus") }.buttonStyle(.glass).disabled(store.storageBlocked)
                Button { toggleVocabulary() } label: { Image(systemName:"chevron.down") }.buttonStyle(.plain).accessibilityLabel("Collapse vocabulary")
            }
            if store.vocabulary.meanings.isEmpty {
                VStack(spacing:8) {
                    Text("A vocabulary that belongs to you").font(.callout.weight(.medium))
                    Text("Give a sign a short name and write the full instruction it should add.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:4),spacing:10) {
                        ForEach(store.vocabulary.meanings.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }) { meaning in
                            Button { store.detail = meaning } label: { VocabularyTile(meaning:meaning,selected:store.composer.parts.contains(where:{$0.meaningID == meaning.id})) }
                                .buttonStyle(.plain).accessibilityLabel("\(meaning.text), \(meaning.learned ? "sign taught" : "phrase only")")
                        }
                    }.padding(2)
                }
            }
        }.frame(height:vocabularyHeight)
    }
}

private struct VocabularyTile: View {
    let meaning: Meaning
    let selected: Bool
    var body: some View {
        VStack(spacing:7) {
            if let example = meaning.examples.first { PoseDrawing(signature:example).frame(height:62) }
            else { Image(systemName:meaning.symbol.rawValue).font(.system(size:26,weight:.light)).frame(height:62) }
            Text(meaning.text).font(.system(size:13,weight:.medium)).lineLimit(1)
            Text(meaning.learned ? meaning.promptRole.label : "Phrase · sign not taught").font(.system(size:10)).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity).padding(10).foregroundStyle(selected ? .indigo : .primary)
            .background(selected ? .indigo.opacity(0.12) : .white.opacity(0.20),in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.6)))
    }
}

private struct WindowPresentation: NSViewRepresentable {
    let floating: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView,context: Context) {
        let floating = floating
        Task { @MainActor in
            guard let window = view.window else { return }
            window.level = floating ? .floating : .normal
            window.collectionBehavior = floating ? [.canJoinAllSpaces,.fullScreenAuxiliary] : [.managed]
        }
    }
}
