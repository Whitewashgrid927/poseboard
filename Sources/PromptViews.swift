import AppKit
import SwiftUI

struct MeaningView: View {
    @ObservedObject var store: PoseStore
    let meaning: Meaning
    @State private var deleting = false
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Label(meaning.text,systemImage:meaning.symbol.rawValue).font(.title2.weight(.medium))
                Spacer(); Button("Done") { store.detail = nil }.buttonStyle(.glass)
            }
            if let example = meaning.examples.first { PoseDrawing(signature:example).frame(height:150) }
            else { Text("Teach a sign to add this phrase with your hands.").font(.callout).foregroundStyle(.secondary) }
            ScrollView { Text(meaning.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(14) }
                .frame(height:140).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:16))
            HStack {
                Button("Delete",role:.destructive) { deleting = true }.buttonStyle(.borderless).disabled(store.storageBlocked)
                Spacer()
                Button("Edit text") { store.beginTeaching(meaning,editText:true) }.buttonStyle(.glass).disabled(store.storageBlocked)
                Button(meaning.learned ? "Teach again" : "Teach sign") { store.beginTeaching(meaning) }.buttonStyle(.glass).disabled(store.storageBlocked)
                Button("Add to prompt") { store.choose(meaning) }.buttonStyle(.glassProminent).tint(.indigo).disabled(store.composer.isEdited)
            }
        }.padding(28).frame(width:600)
            .confirmationDialog("Delete this phrase and its saved sign?",isPresented:$deleting,titleVisibility:.visible) {
                Button("Delete",role:.destructive) { store.remove(meaning) }
            }
    }
}

struct PromptEditor: View {
    let title: String
    let subtitle: String
    let initial: String
    let limit: Int
    var allowsEmpty = false
    let save: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
            TextEditor(text:$text).font(.body).frame(height:260).padding(8)
                .overlay(RoundedRectangle(cornerRadius:12).stroke(Color.secondary.opacity(0.3))).accessibilityLabel(title)
            HStack {
                Text("\(text.count) / \(limit)").font(.caption).foregroundStyle(text.count > limit ? .red : .secondary)
                Spacer(); Button("Cancel") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Save") { save(text) }.buttonStyle(.glassProminent).tint(.indigo)
                    .disabled(text.count > limit || (!allowsEmpty && text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
            }
        }.padding(28).frame(width:640).onAppear { text = initial }
    }
}

struct ReviewView: View {
    @ObservedObject var store: PoseStore
    let review: PromptReview
    private var inserting: Bool { if case .service = review.destination { true } else { false } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Label(inserting ? "Confirm insertion" : "Review your prompt",systemImage:"checkmark.shield").font(.title2.weight(.semibold))
            Text(inserting ? "Return this exact text to the field that requested it. The destination app controls insertion; Poseboard never presses Send." : "Copy this exact text, then paste it into your AI chat. Nothing is sent automatically.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView { Text(review.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(16) }
                .frame(height:260).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:16))
            HStack {
                Text("Sign additions are paused during review.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { store.cancelDelivery() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button(inserting ? "Confirm & insert" : "Confirm & copy") { deliver() }
                    .buttonStyle(.glassProminent).tint(.indigo)
            }
        }.padding(28).frame(width:650)
    }
    private func deliver() {
        guard let (text,destination) = store.confirmPrompt(id:review.id) else { return }
        switch destination {
        case .clipboard:
            let board = NSPasteboard.general
            board.clearContents()
            if board.setString(text,forType:.string) {
                // Clipboard managers can honor this hint; Poseboard keeps no clipboard history.
                board.setData(Data(),forType:.init("org.nspasteboard.TransientType"))
                store.notice = "Copied. Paste into your chat when ready."
            } else { store.error = "The clipboard could not be updated. Your draft is still here." }
        case .service(let id):
            guard store.serviceID == id else { return }
            store.finishService?(text)
        }
    }
}

struct InsertionHelp: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Insert into your AI chat",systemImage:"text.cursor").font(.title2.weight(.semibold))
            Text("1. Place the cursor in your chat’s draft field.")
            Text("2. In that app’s menu, choose Services → Insert Poseboard Prompt.")
            Text("3. Review your prompt in Poseboard, then choose Confirm & insert.")
            Text("Keep the destination field unchanged until you confirm. The request expires after 90 seconds. You can assign a shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services.").font(.callout).foregroundStyle(.secondary)
            Text("If an app does not offer text Services, use Review & copy, then paste manually. This route preserves Poseboard’s camera-only sandbox.").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.glassProminent) }
        }.padding(30).frame(width:560)
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Only on your Mac",systemImage:"lock.shield").font(.title2.weight(.semibold))
            Text("Apple Vision processes camera frames in memory. Poseboard does not record images, use a microphone, or connect to a network. Your own phrases and normalized hand landmarks stay in local storage.")
            Text("Signs add exact saved text. Depth adds a visible instruction. Context and assembled drafts stay in memory and disappear when you quit. No language model rewrites your words.")
            Text("Review the exact prompt before copying or returning it through a macOS text Service. Poseboard does not read other apps, simulate keystrokes, or press Send.")
            Text("Camera startup is explicit. Capture pauses when inactive unless you enable Float; the floating window must remain visible. Hiding or closing the window, sleep, and session lock always pause it.")
            Text("Exactly two confident hands, a stable match, and a clear difference from other signs are required. Lower both hands between signs. This is your personal vocabulary of stationary poses.").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.glassProminent) }
        }.padding(30).frame(width:570)
    }
}
