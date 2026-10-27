import SwiftUI

struct TeachView: View {
    @ObservedObject var store: PoseStore
    private var session: Teaching { store.teaching ?? Teaching() }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(session.editingID == nil ? "Teach a pose" : "Teach your pose").font(.system(size:24,weight:.semibold,design:.rounded))
                    Text("One meaning. Two hands. Three examples.").font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { store.cancelCapture();store.teaching = nil }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
            }.padding(24)
            HStack(alignment:.top,spacing:22) {
                VStack(alignment:.leading,spacing:16) {
                    Text("What does it mean?").font(.system(size:14,weight:.semibold))
                    TextField("Your message",text:Binding(get:{session.text},set:{store.teaching?.text = String($0.prefix(100))}))
                        .textFieldStyle(.roundedBorder).font(.system(size:17)).disabled(session.capturing)
                    Text("Choose a symbol").font(.system(size:12)).foregroundStyle(.secondary)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:4),spacing:8) {
                        ForEach(MeaningSymbol.allCases,id:\.self) { symbol in
                            Button { store.teaching?.symbol = symbol } label: {
                                Image(systemName:symbol.rawValue).font(.system(size:19)).frame(width:40,height:38)
                                    .foregroundStyle(session.symbol == symbol ? Color.indigo : .secondary)
                                    .background(session.symbol == symbol ? Color.indigo.opacity(0.14) : Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:11))
                            }.buttonStyle(.plain).help(symbol.label).accessibilityLabel(symbol.label).disabled(session.capturing)
                        }
                    }
                    Divider()
                    Text("Hold a comfortable pose with both hands. Keep your wrists and fingers visible, with some space between your hands.").font(.system(size:13)).fixedSize(horizontal:false,vertical:true)
                    Text("After each example, relax your hands and repeat the same pose. Camera images are never saved.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                }.frame(width:235)
                VStack(spacing:14) {
                    CameraStage(store:store,compact:true).frame(width:490,height:310).clipShape(RoundedRectangle(cornerRadius:22))
                    HStack(spacing:9) {
                        ForEach(0..<3) { index in
                            Label("Example \(index+1)",systemImage:session.examples.count > index ? "checkmark.circle.fill" : "circle")
                                .font(.system(size:12,weight:.medium)).foregroundStyle(session.examples.count > index ? Color.indigo : .secondary)
                        }
                    }
                    Text(session.instruction).font(.system(size:13,weight:.medium)).multilineTextAlignment(.center).frame(height:36)
                    ProgressView(value:session.capturing ? session.progress : Double(session.examples.count)/3).tint(.indigo)
                }
            }.padding(.horizontal,24)
            HStack {
                if !session.examples.isEmpty { Button("Start over") { store.restartTeaching() }.buttonStyle(.borderless) }
                Spacer()
                if session.finished {
                    Button("Save pose") { store.saveTeaching() }.buttonStyle(.glassProminent).tint(.indigo).keyboardShortcut(.defaultAction)
                } else if session.capturing {
                    Button("Pause capture") { store.cancelCapture() }.buttonStyle(.glass)
                } else {
                    Button("Capture example \(session.examples.count+1)") { store.captureExample() }
                        .buttonStyle(.glassProminent).tint(.indigo)
                        .disabled(!store.running || session.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }.padding(24)
        }.frame(width:795)
            .alert("Could not save this pose",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) { Button("OK",role:.cancel) { store.error = nil } } message:{ Text(store.error ?? "") }
    }
}
