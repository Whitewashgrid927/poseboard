import SwiftUI

struct MainView: View {
    @ObservedObject var store: PoseStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panelHeight: CGFloat = 358
    @State private var dragStart: CGFloat?
    @State private var query = ""
    var body: some View {
        VStack(spacing:0) {
            toolbar
            GeometryReader { geometry in
                let maximum = min(540,geometry.size.height*0.75)
                let height = min(maximum,max(126,panelHeight))
                ZStack(alignment:.bottom) {
                    CameraStage(store:store,bottomInset:height+22)
                    vocabularyPanel(height:height,maximum:maximum)
                        .frame(maxWidth:850).frame(height:height)
                        .padding(.horizontal,28).padding(.bottom,22)
                }.coordinateSpace(name:"stage").clipped()
            }
        }
        .frame(minWidth:820,minHeight:650)
        .background(.background)
        .preferredColorScheme(.light)
        .sheet(isPresented:Binding(get:{store.teaching != nil},set:{if !$0 { store.cancelCapture();store.teaching = nil }})) { TeachView(store:store) }
        .sheet(item:$store.detail) { meaning in MeaningView(store:store,meaning:meaning) }
        .sheet(item:$store.presenting) { meaning in MessageView(meaning:meaning) { store.presenting = nil; store.clearDraft() } }
        .sheet(isPresented:$store.showPrivacy) { PrivacyView() }
        .alert("Poseboard",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) { Button("OK",role:.cancel) { store.error = nil } } message:{ Text(store.error ?? "") }
        .onDisappear { store.stopCamera() }
    }
    private var toolbar: some View {
        ZStack {
            Text("Communicate").font(.system(size:17,weight:.semibold))
            HStack {
                Text("Poseboard").font(.system(size:13,weight:.medium)).foregroundStyle(.secondary).padding(.leading,72)
                Spacer()
                Button { store.showPrivacy = true } label: { Image(systemName:"lock.shield").frame(width:22,height:22) }.buttonStyle(.glass).help("Local storage & privacy").accessibilityLabel("Local storage and privacy")
                Menu {
                    if store.running { Button("Stop camera") { store.stopCamera() } }
                    else { Button("Start camera") { store.startCamera() } }
                    Divider()
                    Button("Default camera") { store.changeCamera(nil) }
                    ForEach(PoseCamera.devices()) { device in Button(device.name) { store.changeCamera(device.id) } }
                } label: { Image(systemName:store.running ? "video.fill" : "video.slash").frame(width:22,height:22) }
                    .menuStyle(.borderlessButton).fixedSize().padding(8).glassEffect(.regular,in:.capsule).help("Camera controls").accessibilityLabel("Camera controls")
            }
        }.padding(.horizontal,18).frame(height:58).background(.ultraThinMaterial)
    }
    private func resize(_ value: CGFloat) { withAnimation(reduceMotion ? nil : .spring(response:0.34,dampingFraction:0.88)) { panelHeight = value } }
    private func vocabularyPanel(height: CGFloat,maximum: CGFloat) -> some View {
        VStack(spacing:0) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width:42,height:4)
                .frame(maxWidth:.infinity).frame(height:24).contentShape(Rectangle())
                .onTapGesture { resize(height > 220 ? 126 : min(358,maximum)) }
                .gesture(DragGesture(coordinateSpace:.named("stage")).onChanged { value in
                    if dragStart == nil { dragStart = height }
                    panelHeight = min(maximum,max(126,(dragStart ?? height)-value.translation.height))
                }.onEnded { _ in
                    dragStart = nil
                    let snaps: [CGFloat] = [126,min(358,maximum),maximum]
                    resize(snaps.min(by:{abs($0-panelHeight)<abs($1-panelHeight)}) ?? 358)
                })
                .accessibilityElement().accessibilityLabel(height > 220 ? "Collapse vocabulary" : "Expand vocabulary")
                .accessibilityAddTraits(.isButton).accessibilityAction { resize(height > 220 ? 126 : min(358,maximum)) }
                .accessibilityAdjustableAction { direction in resize(direction == .increment ? maximum : 126) }
            HStack(spacing:16) {
                Image(systemName:store.draft?.symbol.rawValue ?? "hand.wave").font(.system(size:28,weight:.medium)).foregroundStyle(.indigo)
                    .frame(width:52,height:52).background(.white.opacity(0.25),in:RoundedRectangle(cornerRadius:16))
                VStack(alignment:.leading,spacing:5) {
                    Text(store.draft?.text ?? "Your next message").font(.system(size:25,weight:.medium,design:.rounded)).lineLimit(2).minimumScaleFactor(0.7)
                    Text(store.draftStatus).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength:8)
                if store.draft != nil {
                    Button { store.clearDraft() } label: { Image(systemName:"xmark").font(.system(size:12)) }.buttonStyle(.plain).help("Clear message").accessibilityLabel("Clear message")
                }
                Button { store.showMessage() } label: { HStack { Text("Show"); Image(systemName:"arrow.right") }.padding(.horizontal,10).padding(.vertical,4) }
                    .buttonStyle(.glassProminent).tint(.indigo).disabled(store.draft == nil)
                Button { resize(height > 220 ? 126 : min(358,maximum)) } label: { Image(systemName:height > 220 ? "chevron.down" : "chevron.up") }
                    .buttonStyle(.glass).help(height > 220 ? "Collapse vocabulary" : "Expand vocabulary").accessibilityLabel(height > 220 ? "Collapse vocabulary" : "Expand vocabulary")
            }.padding(.horizontal,24).padding(.bottom,16)
            if height > 220 {
                Rectangle().fill(.primary.opacity(0.08)).frame(height:1).padding(.horizontal,24)
                HStack {
                    Text("Vocabulary").font(.system(size:14,weight:.semibold))
                    Text("\(store.trainedCount) taught").font(.system(size:11)).foregroundStyle(.secondary)
                    Spacer()
                    if store.vocabulary.meanings.count > 9 {
                        TextField("Search",text:$query).textFieldStyle(.roundedBorder).frame(width:130)
                    }
                    Button { store.beginTeaching() } label: { Label("Teach a pose",systemImage:"plus") }.buttonStyle(.glass).disabled(store.storageBlocked)
                }.padding(.horizontal,24).padding(.vertical,12)
                ScrollView {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:3),spacing:10) {
                        ForEach(store.vocabulary.meanings.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }) { meaning in
                            Button { store.detail = meaning } label: {
                                HStack(spacing:13) {
                                    Image(systemName:meaning.symbol.rawValue).font(.system(size:24,weight:.regular)).frame(width:32)
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(meaning.text).font(.system(size:14,weight:.medium)).lineLimit(1)
                                        Text(meaning.learned ? "View pose" : "Not taught yet").font(.system(size:10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength:0)
                                }.foregroundStyle(store.draftID == meaning.id ? Color.indigo : Color.primary)
                                    .padding(14).frame(maxWidth:.infinity,minHeight:68)
                                    .background(store.draftID == meaning.id ? Color.indigo.opacity(0.14) : Color.white.opacity(0.20),in:RoundedRectangle(cornerRadius:17))
                                    .overlay(RoundedRectangle(cornerRadius:17).stroke(store.draftID == meaning.id ? Color.indigo.opacity(0.6) : Color.white.opacity(0.45),lineWidth:1))
                            }.buttonStyle(.plain).accessibilityLabel("\(meaning.text), \(meaning.learned ? "pose taught" : "not taught yet")")
                        }
                    }.padding(.horizontal,24).padding(.bottom,20)
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
            .glassEffect(.regular,in:.rect(cornerRadius:30))
            .shadow(color:.black.opacity(0.12),radius:22,y:10)
    }
}

struct MeaningView: View {
    @ObservedObject var store: PoseStore
    let meaning: Meaning
    @State private var deleting = false
    var body: some View {
        VStack(spacing:20) {
            HStack { Image(systemName:meaning.symbol.rawValue).foregroundStyle(.indigo); Text(meaning.text).lineLimit(2); Spacer(); Button("Done") { store.detail = nil }.buttonStyle(.glass) }.font(.system(size:23,weight:.medium))
            if let example = meaning.examples.first {
                PoseDrawing(signature:example).frame(height:190).background(.indigo.opacity(0.04),in:RoundedRectangle(cornerRadius:20))
                Text("Your saved pose · preview-left and preview-right").font(.system(size:12)).foregroundStyle(.secondary)
            } else {
                Image(systemName:"hands.sparkles").font(.system(size:46,weight:.ultraLight)).foregroundStyle(.indigo).frame(height:90)
                Text("This meaning is ready for your own two-hand pose.").multilineTextAlignment(.center)
                Text("No gesture is assigned until you teach it.").font(.system(size:12)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Delete",role:.destructive) { deleting = true }.buttonStyle(.borderless)
                Spacer()
                Button("Use message") { store.choose(meaning) }.buttonStyle(.glass)
                Button(meaning.learned ? "Teach again" : "Teach this pose") { store.beginTeaching(meaning) }.buttonStyle(.glassProminent).tint(.indigo).disabled(store.storageBlocked)
            }
        }.padding(28).frame(width:520)
            .confirmationDialog("Delete this meaning and its saved pose?",isPresented:$deleting,titleVisibility:.visible) { Button("Delete",role:.destructive) { store.remove(meaning) }; Button("Cancel",role:.cancel) {} }
    }
}
struct MessageView: View {
    let meaning: Meaning
    let done: () -> Void
    var body: some View {
        VStack(spacing:28) {
            Image(systemName:meaning.symbol.rawValue).font(.system(size:88,weight:.light)).foregroundStyle(.indigo)
            Text(meaning.text).font(.system(size:46,weight:.semibold,design:.rounded)).multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(4)
            Button("Done",action:done).buttonStyle(.glass).keyboardShortcut(.cancelAction)
        }.padding(50).frame(width:650,height:420).background(.background)
    }
}
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Only on your Mac",systemImage:"lock.shield").font(.title2.weight(.semibold))
            Text("Camera frames are processed in memory by Apple Vision. Poseboard does not record photos or video, use a microphone, or send data over the network.")
            Text("Teaching saves normalized hand landmarks, your chosen symbols, and your message text in this app’s local storage. You can delete individual entries from the vocabulary.")
            Text("Recognition proposes a message. You choose when to show it. The camera pauses when the app goes into the background, the window closes, or your Mac sleeps or locks.")
            Text("This is a personal vocabulary of held two-hand poses. It does not translate an existing sign language. A camera needs a clear view of both hands; overlapping or hidden fingers may prevent recognition.").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.glassProminent) }
        }.padding(30).frame(width:510)
    }
}
