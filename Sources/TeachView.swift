import SwiftUI

struct TeachView: View {
    @ObservedObject var store: PoseStore
    private var session: Teaching { store.teaching ?? Teaching() }
    private var validText: Bool {
        !session.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty &&
        !session.prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty &&
        session.prompt.count <= 8_000
    }
    var body: some View {
        VStack(spacing:22) {
            HStack {
                VStack(alignment:.leading,spacing:6) {
                    Text(session.editingText ? "Edit your phrase" : "Teach your own sign").font(.system(size:25,weight:.semibold,design:.rounded))
                    Text(session.editingText ? "Change the words. Keep your saved sign." : "One name. Your words. A sign you choose.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { store.cancelCapture(); store.teaching = nil }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
            }
            HStack(alignment:.top,spacing:28) {
                VStack(alignment:.leading,spacing:13) {
                    Text("Short name").font(.callout.weight(.medium))
                    TextField("Name your sign",text:Binding(get:{session.text},set:{store.teaching?.text = String($0.prefix(100))}))
                        .textFieldStyle(.roundedBorder).font(.system(size:17)).disabled(session.capturing)
                    HStack {
                        Picker("Type",selection:Binding(get:{session.role},set:{store.teaching?.role = $0})) {
                            ForEach(PromptRole.allCases,id:\.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("Symbol",selection:Binding(get:{session.symbol},set:{store.teaching?.symbol = $0})) {
                            ForEach(MeaningSymbol.allCases,id:\.self) { Image(systemName:$0.rawValue).tag($0) }
                        }.labelsHidden().frame(width:65)
                    }.disabled(session.capturing)
                    Text("What should this sign add?").font(.callout.weight(.medium))
                    TextEditor(text:Binding(get:{session.prompt},set:{store.teaching?.prompt = $0}))
                        .font(.system(size:14)).frame(height:235).padding(8)
                        .overlay(RoundedRectangle(cornerRadius:12).stroke(Color.secondary.opacity(0.25)))
                        .disabled(session.capturing).accessibilityLabel("Full prompt text")
                    HStack {
                        Text("Sentences and paragraphs, kept verbatim.").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(session.prompt.count) / 8000").foregroundStyle(session.prompt.count > 8_000 ? .red : .secondary)
                    }.font(.system(size:11))
                }.frame(width:405)
                VStack(spacing:14) {
                    if session.editingText, let example = session.examples.first {
                        PoseDrawing(signature:example).frame(width:350,height:235)
                    } else {
                        CameraStage(store:store,compact:true).frame(width:350,height:235).clipShape(RoundedRectangle(cornerRadius:22))
                    }
                    if !session.editingText {
                        HStack(spacing:10) {
                            ForEach(0..<3) { index in
                                Label("Example \(index+1)",systemImage:session.examples.count > index ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size:11,weight:.medium))
                                    .foregroundStyle(session.examples.count > index ? .indigo : .secondary)
                            }
                        }
                        Text(session.instruction).font(.callout.weight(.medium)).multilineTextAlignment(.center).frame(height:42)
                        ProgressView(value:session.capturing ? session.progress : Double(session.examples.count)/3).tint(.indigo)
                        Text("Keep both hands and wrists visible. Hold a comfortable pose, then relax and repeat it for three examples.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else {
                        Text("Your saved hand landmarks stay unchanged.").font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(width:350)
            }
            HStack {
                if !session.editingText {
                    if !session.examples.isEmpty {
                        Button("Start over") { store.restartTeaching() }.buttonStyle(.borderless)
                    } else {
                        Button("Save phrase without a sign") { store.saveTeaching(withoutSign:true) }
                            .buttonStyle(.borderless).disabled(!validText || session.capturing)
                    }
                }
                Spacer()
                if session.finished || session.editingText {
                    Button(session.editingText ? "Save changes" : "Save sign") { store.saveTeaching() }
                        .buttonStyle(.glassProminent).tint(.indigo).disabled(!validText)
                } else if session.capturing {
                    Button("Pause capture") { store.cancelCapture() }.buttonStyle(.glass)
                } else {
                    Button("Capture example \(session.examples.count+1)") { store.captureExample() }
                        .buttonStyle(.glassProminent).tint(.indigo).disabled(!store.running || !validText)
                }
            }
        }.padding(28).frame(width:840)
            .alert("Could not save this sign",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) {
                Button("OK",role:.cancel) { store.error = nil }
            } message:{ Text(store.error ?? "") }
    }
}
