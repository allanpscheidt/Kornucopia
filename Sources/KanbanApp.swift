import SwiftUI
import AppKit

@main
struct KanbanApp: App {
    @NSApplicationDelegateAdaptor(KanbanAppDelegate.self) private var delegate
    @StateObject private var store = BoardStore()
    @StateObject private var localization = AppLocalization.shared

    var body: some Scene {
        Window("Kornucopia", id: "board") {
            BoardView(store: store)
                .frame(minWidth: 1060, minHeight: 640)
                .preferredColorScheme(.light)
                .environment(\.locale, Locale(identifier: localization.language.rawValue))
                .onAppear {
                    delegate.store = store
                    DispatchQueue.main.async { localizeNativeMenus() }
                }
                .onChange(of: localization.language) { _, _ in
                    DispatchQueue.main.async { localizeNativeMenus() }
                }
        }
        .defaultSize(width: 1360, height: 840)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L("settings.title")) {
                    NotificationCenter.default.post(name: .kanbanOpenSettings, object: nil)
                }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button(L("menu.about")) {
                    let alert = NSAlert()
                    alert.messageText = L("app.name")
                    alert.informativeText = L("board.noteStyle") + "\n" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    alert.addButton(withTitle: L("action.close"))
                    alert.runModal()
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button(L("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button(L("action.newCard")) {
                    NotificationCenter.default.post(name: .kanbanNewCard, object: nil)
                }.keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(L("action.undo")) { _ = store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button(L("action.redo")) { _ = store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
            CommandGroup(after: .textEditing) {
                Button(L("board.search")) {
                    NotificationCenter.default.post(name: .kanbanFocusSearch, object: nil)
                }.keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

@MainActor
final class KanbanAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: BoardStore?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuRefreshPending = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification,
                     NSMenu.didRemoveItemNotification, NSMenu.didBeginTrackingNotification] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    localizeNativeMenus()
                    self?.scheduleMenuRefresh()
                }
            })
        }
        scheduleMenuRefresh()
    }
    private func scheduleMenuRefresh() {
        guard !menuRefreshPending else { return }
        menuRefreshPending = true
        RunLoop.main.perform(inModes: [.default, .eventTracking, .common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.menuRefreshPending = false
                localizeNativeMenus()
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, !store.flush() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("error.terminationTitle")
        alert.informativeText = L("error.terminationBody", ["detail": store.saveError ?? ""])
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("action.keepOpen"))
        alert.addButton(withTitle: L("action.quitAnyway"))
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

extension Notification.Name {
    static let kanbanOpenSettings = Notification.Name("kanban.settings")
    static let kanbanNewCard = Notification.Name("kanban.newCard")
    static let kanbanFocusSearch = Notification.Name("kanban.focusSearch")
}
