import SwiftUI
import AppKit

@main
struct KanbanApp: App {
    @NSApplicationDelegateAdaptor(KanbanAppDelegate.self) private var delegate
    @StateObject private var store = BoardStore()

    var body: some Scene {
        Window("Kornucopia", id: "board") {
            BoardView(store: store)
                .frame(minWidth: 1060, minHeight: 640)
                .preferredColorScheme(.light)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1360, height: 840)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Novo cartão") {
                    NotificationCenter.default.post(name: .kanbanNewCard, object: nil)
                }.keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Desfazer") { _ = store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("Refazer") { _ = store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
            CommandGroup(after: .textEditing) {
                Button("Buscar cartões") {
                    NotificationCenter.default.post(name: .kanbanFocusSearch, object: nil)
                }.keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

@MainActor
final class KanbanAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: BoardStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, !store.flush() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "As últimas alterações ainda não foram salvas"
        alert.informativeText = "O Mac não conseguiu gravar o quadro. Mantenha o app aberto para tentar novamente.\n\n" + (store.saveError ?? "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Manter aberto")
        alert.addButton(withTitle: "Sair mesmo assim")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

extension Notification.Name {
    static let kanbanNewCard = Notification.Name("kanban.newCard")
    static let kanbanFocusSearch = Notification.Name("kanban.focusSearch")
}
