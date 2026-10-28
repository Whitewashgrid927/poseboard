import AppKit

/// macOS owns the destination and its private service pasteboard. No key injection or AX access.
@MainActor final class PromptService: NSObject {
    weak var store: PoseStore?
    @objc func insertPrompt(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let store, let window = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }),
              store.beginService(UUID()) else {
            error.pointee = "Finish the current edit or confirmation in Poseboard, then request insertion again."
            return
        }
        var result: String?
        var finished = false
        let started = ProcessInfo.processInfo.systemUptime
        store.finishService = { text in
            guard !finished else { return }
            finished = true
            if ProcessInfo.processInfo.systemUptime-started < 90 { result = text }
            NSApp.stopModal()
        }
        let timeout = Timer(timeInterval:90,repeats:false) { _ in
            Task { @MainActor in store.cancelDelivery() }
        }
        RunLoop.main.add(timeout,forMode:.common)
        RunLoop.main.add(timeout,forMode:.modalPanel)
        defer {
            timeout.invalidate()
            store.endService()
        }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if !store.composer.isEmpty { store.reviewPrompt() }
        NSApp.runModal(for:window)
        guard finished, let result, ProcessInfo.processInfo.systemUptime-started < 90,
              (try? PromptText.validate(result)) != nil else {
            error.pointee = "Insertion canceled or expired. Your Poseboard draft is unchanged."
            return
        }
        pasteboard.clearContents()
        guard pasteboard.setString(result,forType:.string) else {
            error.pointee = "The text could not be returned. Your Poseboard draft is unchanged."
            return
        }
        store.notice = "Confirmed text returned to the requesting field. Nothing was sent."
    }
}
