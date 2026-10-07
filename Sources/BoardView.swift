import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum BoardSheet: Identifiable {
    case card(UUID), settings
    var id: String {
        switch self { case .card(let id): return id.uuidString; case .settings: return "settings" }
    }
}

struct BoardView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject private var localization = AppLocalization.shared
    @State private var query = ""
    @State private var sheet: BoardSheet?
    @State private var restoredSession = false
    @FocusState private var searchFocused: Bool

    private var sessionKey: String {
        "editingCardID." + (ProcessInfo.processInfo.environment["KORNUCOPIA_DATA_DIR"] ?? ProcessInfo.processInfo.environment["KANBAN_DATA_DIR"] ?? "personal")
    }

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            header
            HStack(alignment: .top, spacing: 16) {
                ForEach(KanbanColumn.allCases, id: \.self) { column in
                    ColumnView(store: store, column: column, query: query,
                               openCard: { sheet = .card($0) },
                               addCard: { create(in: column) })
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
            footer
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .background(WindowConfiguration())
        .onReceive(NotificationCenter.default.publisher(for: .kanbanNewCard)) { _ in
            if sheet == nil { create(in: .backlog) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanbanOpenSettings)) { _ in
            if sheet == nil { sheet = .settings }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanbanFocusSearch)) { _ in
            if sheet == nil { searchFocused = true }
        }
        .onAppear {
            if NSApp.isRunning { DispatchQueue.main.async { restoreSession() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanbanReady)) { _ in restoreSession() }
        .onChange(of: sheet?.id) { _, _ in
            if case .card(let id) = sheet { AppPreferences.defaults.set(id.uuidString, forKey: sessionKey) }
            else { AppPreferences.defaults.removeObject(forKey: sessionKey) }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .card(let id): CardEditor(store: store, cardID: id)
            case .settings: SettingsView(store: store)
            }
        }
        .onChange(of: store.wipAlert) { _, show in
            guard show else { return }
            store.wipAlert = false
            let alert = NSAlert()
            alert.messageText = L("wip.title")
            alert.informativeText = L("wip.body", ["limit": String(store.snapshot.wipLimit)])
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("action.understood"))
            alert.runModal()
        }
        .onChange(of: store.storageAlert) { _, key in
            guard let key else { return }
            store.storageAlert = nil
            let alert = NSAlert()
            alert.messageText = L("storage.alertTitle")
            alert.informativeText = L(key) + "\n\n" + L("storage.editRejected")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("action.understood"))
            alert.runModal()
        }
    }

    private var topStrip: some View {
        HStack(spacing: 8) {
            Image(nsImage: Theme.logo).resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
            Text(L("app.name").uppercased()).tracking(2).fontWeight(.semibold)
            Spacer()
            Image(systemName: "lock").accessibilityHidden(true)
            Text(L("board.localAccess"))
        }
        .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 28).frame(height: 38).background(Theme.night)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("board.personalTitle")).font(.system(size: 10, weight: .bold))
                    .tracking(1.5).foregroundStyle(Theme.accent)
                Text(store.snapshot.boardTitle).font(.system(size: 30, weight: .bold))
                    .tracking(-0.7).foregroundStyle(Theme.strong).lineLimit(1).help(store.snapshot.boardTitle)
                Text(L("board.summary"))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary).accessibilityHidden(true)
                TextField(L("board.search"), text: $query).textFieldStyle(.plain)
                    .focused($searchFocused).accessibilityLabel(L("board.search"))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel(L("board.clearSearch"))
                }
            }
            .font(.system(size: 13)).padding(12).frame(width: 218)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(searchFocused ? Theme.accent : Theme.line, lineWidth: searchFocused ? 2 : 1))
            Button { create(in: .backlog) } label: {
                Label(L("action.newCard"), systemImage: "plus").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16).frame(height: 42)
            }
            .buttonStyle(PrimaryButtonStyle()).help(L("board.newBacklogHint"))
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 42, height: 42)
            }
            .buttonStyle(QuietButtonStyle()).accessibilityLabel(L("settings.title")).help(L("board.settingsHint"))
        }
        .padding(.horizontal, 28).padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: store.saveError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                .accessibilityHidden(true)
            if let error = store.saveError {
                Text(error).lineLimit(2)
                Button(L("action.retrySave")) { _ = store.flush() }.buttonStyle(.borderless)
            } else {
                Text(L("board.saved"))
            }
            Spacer()
            Text(localization.cardCount(store.snapshot.cards.count))
            Rectangle().fill(Theme.line).frame(width: 1, height: 12).padding(.horizontal, 6)
            Button(L("board.doingLimit", ["limit": String(store.snapshot.wipLimit)])) { sheet = .settings }
                .buttonStyle(.plain).foregroundStyle(Theme.strong)
        }
        .font(.system(size: 11)).foregroundStyle(store.saveError == nil ? Theme.secondary : Theme.warning)
        .padding(.horizontal, 28).padding(.vertical, 13)
        .background(Color.white.opacity(0.7)).overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    private func create(in column: KanbanColumn) {
        if let id = store.createCard(in: column, color: .yellow) { query = ""; sheet = .card(id) }
    }

    private func restoreSession() {
        guard !restoredSession else { return }
        restoredSession = true
        if let message = store.recoveryMessage {
            let alert = NSAlert()
            alert.messageText = L("recovery.title")
            alert.informativeText = message
            alert.addButton(withTitle: L("action.understood"))
            alert.runModal()
        }
        if let value = AppPreferences.defaults.string(forKey: sessionKey),
           let id = UUID(uuidString: value), store.card(id: id) != nil { sheet = .card(id) }
    }
}

private struct ColumnView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject private var localization = AppLocalization.shared
    let column: KanbanColumn
    let query: String
    let openCard: (UUID) -> Void
    let addCard: () -> Void
    @State private var isTargeted = false
    @State private var tutorialExpanded = true

    private var visibleCards: [KanbanCard] { store.cards(in: column, query: query) }
    private var count: Int { store.cards(in: column, query: "").count }
    private var isFull: Bool { column == .doing && count >= store.snapshot.wipLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle().fill(column.dot).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(column.title).font(.system(size: 16, weight: .bold))
                    Spacer(minLength: 2)
                    Text(column == .doing ? "\(count)/\(store.snapshot.wipLimit)" : "\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isFull ? Theme.warning : Theme.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isFull ? Color(hex: 0xFAEBD4) : Color.white.opacity(0.75), in: Capsule())
                        .accessibilityLabel(column == .doing ? L("a11y.doingCount", ["count": String(count), "limit": String(store.snapshot.wipLimit)]) : localization.cardCount(count))
                    Button(action: addCard) { Image(systemName: "plus").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                        .accessibilityLabel(L("a11y.addColumnCard", ["column": column.title]))
                        .help(L("a11y.addColumnCard", ["column": column.title]))
                }
                Text(column.subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                DisclosureGroup(isExpanded: $tutorialExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("column." + column.rawValue + ".tutorial.title"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.strong)
                        ForEach(1...3, id: \.self) { step in
                            HStack(alignment: .top, spacing: 7) {
                                Text(String(step) + ".").fontWeight(.semibold)
                                Text(L("column." + column.rawValue + ".tutorial.step" + String(step),
                                       ["limit": String(store.snapshot.wipLimit)]))
                            }
                        }
                        Text(L("column." + column.rawValue + ".tutorial.next"))
                            .fontWeight(.medium).foregroundStyle(Theme.strong)
                    }
                    .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                } label: {
                    Label(L("tutorial.toggle"), systemImage: "questionmark.circle")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.strong)
                }
                .padding(.top, 6)
            }
            .padding(16)
            Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 1).padding(.horizontal, 16)
            ScrollView(.vertical) {
                LazyVStack(spacing: 12) {
                    ForEach(visibleCards) { card in
                        StickyCard(card: card, open: { openCard(card.id) }, store: store)
                            .dropDestination(for: String.self) { values, _ in
                                moveDroppedCard(values, store: store, column: column, before: card.id)
                            }
                    }
                    if visibleCards.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: query.isEmpty ? column.emptySymbol : "magnifyingglass")
                                .font(.system(size: 24, weight: .light)).foregroundStyle(column.dot).accessibilityHidden(true)
                            Text(query.isEmpty ? column.emptyTitle : L("board.noResults"))
                                .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                            Text(query.isEmpty ? (column == .doing ? L("column.doing.emptyHelp", ["limit": String(store.snapshot.wipLimit)]) : column.emptyHelp) : L("board.searchAgain"))
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 40)
                    }
                    Button(action: addCard) {
                        Label(L("action.addCard"), systemImage: "plus").font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    .accessibilityLabel(L("a11y.newColumnCard", ["column": column.title]))
                    Color.clear.frame(height: 28).accessibilityHidden(true)
                }
                .padding(14).frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .dropDestination(for: String.self, action: { values, _ in
                moveDroppedCard(values, store: store, column: column, before: nil)
            }, isTargeted: { isTargeted = $0 })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.column.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isTargeted ? Theme.accent : Theme.line.opacity(0.65), lineWidth: isTargeted ? 2 : 1))
        .onAppear { tutorialExpanded = AppPreferences.tutorialExpanded(for: column.rawValue) }
        .onChange(of: tutorialExpanded) { _, value in
            AppPreferences.defaults.set(value, forKey: "tutorial." + column.rawValue)
        }
    }
}

private struct StickyCard: View {
    let card: KanbanCard
    let open: () -> Void
    @ObservedObject var store: BoardStore
    @ObservedObject private var localization = AppLocalization.shared
    @State private var hover = false

    var body: some View {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    RoundedRectangle(cornerRadius: 2).fill(card.color.mark.opacity(0.6)).frame(width: 25, height: 3)
                    Spacer()
                    Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.ink.opacity(0.6))
                }.accessibilityHidden(true)
                Text(card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("card.untitled") : card.title)
                    .font(.system(size: 15, weight: .semibold)).lineLimit(4)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if !card.notes.isEmpty {
                    Text(card.notes).font(.system(size: 12)).lineSpacing(3).lineLimit(4)
                        .multilineTextAlignment(.leading).foregroundStyle(Theme.ink.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(card.color.title).font(.system(size: 10)).foregroundStyle(Theme.ink.opacity(0.75))
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10)).foregroundStyle(Theme.ink.opacity(0.65))
                }.accessibilityHidden(true)
            }
            .foregroundStyle(Theme.ink).padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(card.color.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(card.color.mark.opacity(hover ? 0.65 : 0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(hover ? 0.10 : 0.055), radius: hover ? 7 : 4, x: 0, y: 3)
            .contentShape(Rectangle())
            .kanbanDraggable(card.id)
        .onTapGesture(perform: open)
        .onHover { hover = $0 }
        .focusable()
        .onKeyPress(.return) { open(); return .handled }
        .onKeyPress(.space) { open(); return .handled }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityLabel(L("a11y.cardLabel", ["title": card.title.isEmpty ? L("card.untitled") : card.title, "column": card.column.title]))
        .accessibilityHint(L("a11y.cardOpenHint"))
        .help(L("a11y.cardUsageHint"))
        .contextMenu {
            Button(L("menu.editCard"), action: open)
            Menu(L("menu.moveTo")) {
                ForEach(KanbanColumn.allCases.filter { $0 != card.column }, id: \.self) { column in
                    Button(column.title) { _ = store.moveCard(id: card.id, to: column, before: nil) }
                }
            }
            Button(L("menu.moveFirst")) {
                _ = store.moveCard(id: card.id, to: card.column, before: store.cards(in: card.column, query: "").first?.id)
            }
            Button(L("menu.moveLast")) { _ = store.moveCard(id: card.id, to: card.column, before: nil) }
            Divider()
            Button(L("action.deleteCard"), role: .destructive) { _ = store.deleteCard(id: card.id) }
        }
    }
}

@MainActor
private func moveDroppedCard(_ values: [String], store: BoardStore, column: KanbanColumn, before: UUID?) -> Bool {
    guard let value = values.first, value.hasPrefix("kanban:"),
          let id = UUID(uuidString: String(value.dropFirst(7))), store.card(id: id) != nil else { return false }
    return store.moveCard(id: id, to: column, before: before)
}

private extension View {
    @ViewBuilder
    func kanbanDraggable(_ id: UUID) -> some View {
        if #available(macOS 26.0, *) {
            self.draggable("kanban:" + id.uuidString)
                .dragConfiguration(DragConfiguration(allowMove: true))
        } else {
            self.onDrag { NSItemProvider(object: ("kanban:" + id.uuidString) as NSString) }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.white)
            .background(configuration.isPressed ? Theme.strong : Theme.accent, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Theme.secondary)
            .background(configuration.isPressed ? Theme.column : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}

private struct WindowConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfigurationView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class ConfigurationView: NSView {
        private var closeGuard: WindowCloseGuard?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.setFrameAutosaveName(AppPreferences.scopeID == "personal" ? "KornucopiaBoard" : "KornucopiaBoard." + AppPreferences.scopeID)
            window.backgroundColor = NSColor(red: 244/255, green: 248/255, blue: 247/255, alpha: 1)
            if closeGuard == nil {
                let guardDelegate = WindowCloseGuard(previous: window.delegate)
                closeGuard = guardDelegate
                window.delegate = guardDelegate
            }
        }
    }
}

/// Preserve SwiftUI's delegate behavior while checking drafts before closing the window.
@MainActor
private final class WindowCloseGuard: NSObject, NSWindowDelegate {
    private let previous: NSWindowDelegate?
    init(previous: NSWindowDelegate?) { self.previous = previous; super.init() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard PendingEditorDraft.permitsClosing() else { return false }
        return previous?.windowShouldClose?(sender) ?? true
    }
    nonisolated override func responds(to selector: Selector!) -> Bool {
        MainActor.assumeIsolated { super.responds(to: selector) || previous?.responds(to: selector) == true }
    }
    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        MainActor.assumeIsolated { previous }
    }
}
