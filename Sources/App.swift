import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: PoseStore?
    let promptService = PromptService()
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.servicesProvider = promptService }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { store?.cancelDelivery(); store?.stopCamera(); return .terminateNow }
}
@main struct PoseboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = PoseStore()
    var body: some Scene {
        Window("Poseboard",id:"main") {
            MainView(store:store).onAppear { delegate.store = store; delegate.promptService.store = store }
        }
        .defaultSize(width:1060,height:840)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing:.newItem) { Button("Teach a sign…") { store.beginTeaching() }.keyboardShortcut("n").disabled(store.teaching != nil || store.storageBlocked || store.review != nil) }
            CommandMenu("Camera") {
                Button("Start camera") { store.startCamera() }.disabled(store.running)
                Button("Stop camera") { store.stopCamera() }.keyboardShortcut(".",modifiers:[.command,.shift])
            }
            CommandGroup(replacing:.help) { Button("Local storage & privacy") { store.showPrivacy = true } }
        }
    }
}
