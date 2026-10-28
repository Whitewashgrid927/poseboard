import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var store: PoseStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var expanded = false
    @State private var vocabularyHeight: CGFloat = 170
    @State private var dragStart: CGFloat?
    @State private var query = ""
    @State private var clearConfirmation = false
    var body: some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.89,green:0.93,blue:0.99),Color(red:0.97,green:0.93,blue:0.94),Color(red:0.85,green:0.91,blue:0.98)],startPoint:.topLeading,endPoint:.bottomTrailing)
            VStack(spacing:12) {
                toolbar.padding(.horizontal,28).padding(.top,12)
                HStack(spacing:20) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(store.running ? store.trackingText : "Your signs. Your thoughts.").font(.callout.weight(.medium))
                        Text(store.composer.isEdited ? "Manual draft · choose Use signs to resume composing." :
                             store.running && store.needsRelease ? "Lower both hands before the next sign." :
                             "Add context, then make a sign or choose a phrase.")
                            .font(.caption).foregroundStyle(store.running && store.needsRelease ? .indigo : .secondary)
                    }
                    Spacer()
                    if store.running { cameraTile.frame(width:140,height:72) }
                    else if store.cameraState == .starting { ProgressView().controlSize(.small) }
                    else {
                        Button { store.startCamera() } label: { Label("Start camera",systemImage:"video") }.buttonStyle(.glass)
                    }
                }.padding(.horizontal,38)
                ScrollView {
                    composerPanel.padding(.horizontal,28).padding(.top,2).padding(.bottom,12)
                }
                vocabularyPanel.padding(.horizontal,28).padding(.bottom,16)
            }
        }
        .frame(minWidth:900,minHeight:720)
        .preferredColorScheme(.light)
        .background(WindowPresentation(floating:store.floating))
        .sheet(isPresented:Binding(get:{store.teaching != nil},set:{if !$0 { store.cancelCapture(); store.teaching = nil }})) { TeachView(store:store) }
        .sheet(item:$store.detail) { MeaningView(store:store,meaning:$0) }
        .sheet(item:Binding(get:{store.review},set:{if $0 == nil { store.cancelReview() }})) { ReviewView(store:store,review:$0) }
        .sheet(isPresented:$store.editingDraft) {
            PromptEditor(title:"Edit your prompt",subtitle:"Editing pauses sign additions and freezes the card composition. Choose Use signs to return to it.",initial:store.composer.text,limit:PromptText.limit) { store.editPrompt($0) }
        }
        .sheet(item:$store.contextEditor) { ContextEditor(store:store,session:$0) }
        .sheet(isPresented:$store.showPrivacy) { PrivacyView() }
        .sheet(isPresented:$store.showInsertionHelp) { InsertionHelp() }
        .alert("Poseboard",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) { Button("OK",role:.cancel) { store.error = nil } } message:{ Text(store.error ?? "") }
        .confirmationDialog("Clear this prompt and all its context cards?",isPresented:$clearConfirmation,titleVisibility:.visible) {
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
                ContextCardsView(store:store)
                HStack {
                    Text("Your signs").font(.headline)
                    Spacer()
                    if store.serviceID != nil {
                        Label("Insertion requested",systemImage:"text.cursor").font(.caption).foregroundStyle(.indigo)
                        Button("Cancel insertion") { store.cancelDelivery() }.buttonStyle(.borderless)
                    } else {
                        Menu {
                            ForEach(PromptStarter.allCases) { starter in
                                Menu(starter.title) {
                                    Button("Add phrase") { store.choose(starter.meaning) }
                                    Button("Teach my sign") { store.beginTeaching(starter.meaning) }.disabled(store.storageBlocked)
                                }
                            }
                        } label: { Label("Starter phrases",systemImage:"sparkle") }
                            .menuStyle(.borderlessButton).fixedSize().font(.caption).disabled(store.composer.isEdited)
                    }
                }
                signChips
                HStack(spacing:16) {
                    Text("Depth").font(.caption).foregroundStyle(.secondary)
                    Picker("Depth",selection:Binding(get:{store.composer.depth},set:{ store.setDepth($0) })) {
                        ForEach(PromptDepth.allCases,id:\.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth:440).labelsHidden().disabled(store.composer.isEdited)
                    Spacer()
                    Text("Your words, kept exact").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(store.composer.isEdited ? "Your edited prompt" : "Live prompt").font(.headline)
                    if !store.composer.isEdited {
                        Label("Local",systemImage:"circle.fill").font(.system(size:10)).foregroundStyle(.indigo)
                    }
                    Spacer()
                    if store.composer.isEdited {
                        Button("Use signs") { store.useSigns() }.font(.caption).buttonStyle(.borderless)
                    }
                    Button("Edit text") { store.editingDraft = true }.font(.caption).buttonStyle(.borderless).disabled(store.composer.isEmpty)
                }
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if store.composer.isEmpty {
                            Text("Your prompt takes shape here as you combine signs and context.").foregroundStyle(.secondary)
                        }
                        ForEach(store.composer.blocks) { block in
                            Text(block.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                                .foregroundStyle(block.kind == .depth ? .indigo : .primary)
                                .padding(block.kind == .depth ? 9 : 0)
                                .background(block.kind == .depth ? Color.indigo.opacity(0.07) : .clear,in:RoundedRectangle(cornerRadius:10))
                        }
                    }.font(.system(size:16)).frame(maxWidth:.infinity,alignment:.leading).padding(16)
                }.frame(height:170)
                    .background(reduceTransparency ? Color.white : .white.opacity(0.43),in:RoundedRectangle(cornerRadius:19))
                    .accessibilityLabel("Live prompt preview")
                if case .failed(let message) = store.cameraState {
                    Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                }
            }.padding(22)
                .glassEffect(.regular,in:.rect(cornerRadius:30))
                .shadow(color:.black.opacity(0.08),radius:16,y:8)
        }
    }
    private var vocabularyPanel: some View {
        GlassEffectContainer(spacing:12) {
            VStack(spacing:8) {
                HStack(spacing:14) {
                    Button { store.undoSign() } label: { Label("Undo",systemImage:"arrow.uturn.backward") }
                        .buttonStyle(.borderless).disabled(store.composer.parts.isEmpty || store.composer.isEdited)
                    Button("Clear") { clearConfirmation = true }.buttonStyle(.borderless).disabled(!store.composer.hasContent)
                    Spacer()
                    Text("Nothing is inserted until you confirm.")
                        .font(.system(size:11)).foregroundStyle(.secondary)
                    Button("Review prompt") { store.reviewPrompt() }
                        .buttonStyle(.glassProminent).tint(.indigo).disabled(store.composer.isEmpty)
                }
                HStack(spacing:12) {
                    if let notice = store.notice {
                        Text(notice).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Connect to a text field") { store.showInsertionHelp = true }
                        .buttonStyle(.borderless).font(.caption).disabled(store.serviceID != nil)
                }
                handle
                HStack {
                    Button { toggleVocabulary() } label: {
                        HStack(spacing:8) {
                            Text("Your vocabulary").font(.system(size:14,weight:.semibold))
                            Image(systemName:expanded ? "chevron.down" : "chevron.up").font(.caption)
                        }
                    }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse vocabulary" : "Expand vocabulary")
                    Text("\(store.trainedCount) signs").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if expanded && store.vocabulary.meanings.count > 6 { TextField("Search",text:$query).textFieldStyle(.roundedBorder).frame(width:120) }
                    Button { store.beginTeaching() } label: { Label("Teach a sign",systemImage:"plus") }.buttonStyle(.glass).disabled(store.storageBlocked)
                }
                if expanded { vocabulary }
            }.padding(.horizontal,22).padding(.vertical,14)
                .glassEffect(.regular,in:.rect(cornerRadius:26))
                .shadow(color:.black.opacity(0.08),radius:16,y:8)
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
                    Text("Make a taught sign, or try").font(.callout).foregroundStyle(.secondary)
                    ForEach(PromptStarter.allCases) { starter in
                        Button(starter.title) { store.choose(starter.meaning) }.buttonStyle(.glass).disabled(store.composer.isEdited)
                    }
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
