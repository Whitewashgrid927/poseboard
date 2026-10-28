import SwiftUI

struct ContextCardsView: View {
    @ObservedObject var store: PoseStore
    @State private var removing: PromptContext?
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.firstTextBaseline) {
                Text("Context").font(.headline)
                Text("Only included cards enter your prompt").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { store.beginContext() } label: { Label("Add context",systemImage:"plus") }
                    .buttonStyle(.glass)
                    .disabled(store.composer.isEdited || store.composer.contexts.count >= PromptContext.maximumCards)
            }
            if store.composer.contexts.isEmpty {
                HStack(spacing:14) {
                    Image(systemName:"doc.text").font(.system(size:25,weight:.light)).foregroundStyle(.indigo)
                    VStack(alignment:.leading,spacing:4) {
                        Text("Give your prompt something to work with").font(.callout.weight(.medium))
                        Text("Add a passage, an idea, or two approaches to compare. You choose the text.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
                    .background(.white.opacity(0.28),in:RoundedRectangle(cornerRadius:20))
            } else {
                LazyVGrid(columns:[GridItem(.flexible(),spacing:12),GridItem(.flexible())],spacing:12) {
                    ForEach(store.composer.contexts) { card in
                        VStack(alignment:.leading,spacing:9) {
                            HStack(spacing:8) {
                                Image(systemName:"doc.text").foregroundStyle(.indigo)
                                Text(card.title).font(.callout.weight(.semibold)).lineLimit(1)
                                Spacer(minLength:4)
                                Menu {
                                    Button("Edit context") { store.beginContext(card) }
                                    Button("Remove context",role:.destructive) { removing = card }
                                } label: { Image(systemName:"ellipsis") }
                                    .menuStyle(.borderlessButton).fixedSize()
                                    .accessibilityLabel("Options for \(card.title)")
                            }
                            Text(card.body).font(.system(size:12)).foregroundStyle(.secondary)
                                .lineLimit(2).frame(maxWidth:.infinity,minHeight:32,alignment:.topLeading)
                            Toggle("Include in prompt",isOn:Binding(get:{card.isIncluded},set:{store.includeContext(card,included:$0)}))
                                .toggleStyle(.checkbox).font(.caption).tint(.indigo)
                                .accessibilityLabel("Include \(card.title) in prompt")
                        }.padding(15).frame(maxWidth:.infinity,alignment:.leading)
                            .background(card.isIncluded ? Color.indigo.opacity(0.07) : .white.opacity(0.22),in:RoundedRectangle(cornerRadius:20))
                            .overlay(RoundedRectangle(cornerRadius:20).stroke(card.isIncluded ? .indigo.opacity(0.35) : .white.opacity(0.65)))
                            .disabled(store.composer.isEdited)
                    }
                }
            }
        }
        .confirmationDialog("Remove this context card?",isPresented:Binding(get:{removing != nil},set:{if !$0 { removing = nil }}),titleVisibility:.visible) {
            Button("Remove context",role:.destructive) {
                if let card = removing { store.removeContext(card) }
                removing = nil
            }
        } message: { Text("This text is only held in this draft.") }
    }
}

struct ContextEditor: View {
    @ObservedObject var store: PoseStore
    let session: ContextEditing
    @State private var title = ""
    @State private var text = ""
    private var totalCharacters: Int {
        store.composer.contextCharacterCount-(session.card?.body.count ?? 0)+text.count
    }
    private var validationMessage: String? {
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return "Give the card a title and some text." }
        do { try PromptContext(title:title,body:text).validate() }
        catch { return error.localizedDescription }
        return totalCharacters > PromptContext.textLimit ? "All context cards together can hold up to 8,000 characters." : nil
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(session.card == nil ? "Add context" : "Edit context").font(.title2.weight(.semibold))
            Text("Type or paste only what you want to include. This card stays in memory and disappears when you clear the draft or quit.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Card title, such as Option A",text:$title).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Context title")
            TextEditor(text:$text).font(.body).frame(height:230).padding(8)
                .overlay(RoundedRectangle(cornerRadius:12).stroke(.secondary.opacity(0.25)))
                .accessibilityLabel("Context text")
            HStack {
                Text("\(totalCharacters) / 8,000 context characters").font(.caption)
                    .foregroundStyle(totalCharacters > PromptContext.textLimit ? .red : .secondary)
                Spacer()
                Button("Cancel") { store.contextEditor = nil }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Save context") { store.saveContext(title:title,body:text) }
                    .buttonStyle(.glassProminent).tint(.indigo).disabled(validationMessage != nil)
            }
            if let message = validationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(width:620)
            .onAppear { title = session.card?.title ?? ""; text = session.card?.body ?? "" }
            .alert("Could not save context",isPresented:Binding(get:{store.error != nil},set:{if !$0 { store.error = nil }})) {
                Button("OK",role:.cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}
