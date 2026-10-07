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
        .onReceive(NotificationCenter.default.publisher(for: .kanbanFocusSearch)) { _ in
            if sheet == nil { searchFocused = true }
        }
        .onAppear {
            guard !restoredSession else { return }
            restoredSession = true
            if let message = store.recoveryMessage {
                let alert = NSAlert()
                alert.messageText = "Recuperação do quadro"
                alert.informativeText = message
                alert.addButton(withTitle: "Entendi")
                alert.runModal()
            }
            if let value = UserDefaults.standard.string(forKey: sessionKey),
               let id = UUID(uuidString: value), store.card(id: id) != nil { sheet = .card(id) }
        }
        .onChange(of: sheet?.id) { _, _ in
            if case .card(let id) = sheet { UserDefaults.standard.set(id.uuidString, forKey: sessionKey) }
            else { UserDefaults.standard.removeObject(forKey: sessionKey) }
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
            alert.messageText = "Limite de trabalho em progresso"
            alert.informativeText = "Fazendo já tem \(store.snapshot.wipLimit) cartões, o limite atual.\n\nConclua um cartão e mova-o para Revisão antes de começar outro. Guarde novas ideias no Backlog.\n\nVocê pode aumentar o limite nas Configurações."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Entendi")
            alert.runModal()
        }
    }

    private var topStrip: some View {
        HStack(spacing: 8) {
            Image(nsImage: Theme.logo).resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
            Text("KORNUCOPIA").tracking(2).fontWeight(.semibold)
            Spacer()
            Image(systemName: "lock").accessibilityHidden(true)
            Text("Acesso local")
        }
        .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 28).frame(height: 38).background(Theme.night)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ORGANIZAÇÃO PESSOAL").font(.system(size: 10, weight: .bold))
                    .tracking(1.5).foregroundStyle(Theme.accent)
                Text(store.snapshot.boardTitle).font(.system(size: 30, weight: .bold))
                    .tracking(-0.7).foregroundStyle(Theme.strong).lineLimit(1).help(store.snapshot.boardTitle)
                Text("Ideias, produção, revisão e trabalho concluído.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary).accessibilityHidden(true)
                TextField("Buscar cartões", text: $query).textFieldStyle(.plain)
                    .focused($searchFocused).accessibilityLabel("Buscar cartões")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Limpar busca")
                }
            }
            .font(.system(size: 13)).padding(12).frame(width: 218)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(searchFocused ? Theme.accent : Theme.line, lineWidth: searchFocused ? 2 : 1))
            Button { create(in: .backlog) } label: {
                Label("Novo cartão", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16).frame(height: 42)
            }
            .buttonStyle(PrimaryButtonStyle()).help("Novo cartão no Backlog (⌘N)")
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 42, height: 42)
            }
            .buttonStyle(QuietButtonStyle()).accessibilityLabel("Configurações").help("Configurações do quadro")
        }
        .padding(.horizontal, 28).padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: store.saveError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                .accessibilityHidden(true)
            if let error = store.saveError {
                Text(error).lineLimit(2)
                Button("Tentar salvar") { _ = store.flush() }.buttonStyle(.borderless)
            } else {
                Text("Salvo no Mac")
            }
            Spacer()
            Text("\(store.snapshot.cards.count) \(store.snapshot.cards.count == 1 ? "cartão" : "cartões")")
            Rectangle().fill(Theme.line).frame(width: 1, height: 12).padding(.horizontal, 6)
            Button("Limite em Fazendo: \(store.snapshot.wipLimit)") { sheet = .settings }
                .buttonStyle(.plain).foregroundStyle(Theme.strong)
        }
        .font(.system(size: 11)).foregroundStyle(store.saveError == nil ? Theme.secondary : Theme.warning)
        .padding(.horizontal, 28).padding(.vertical, 13)
        .background(Color.white.opacity(0.7)).overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    private func create(in column: KanbanColumn) {
        if let id = store.createCard(in: column, color: .yellow) { query = ""; sheet = .card(id) }
    }
}

private struct ColumnView: View {
    @ObservedObject var store: BoardStore
    let column: KanbanColumn
    let query: String
    let openCard: (UUID) -> Void
    let addCard: () -> Void
    @State private var isTargeted = false

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
                        .accessibilityLabel(column == .doing ? "\(count) \(count == 1 ? "cartão" : "cartões") de um limite de \(store.snapshot.wipLimit)" : "\(count) \(count == 1 ? "cartão" : "cartões")")
                    Button(action: addCard) { Image(systemName: "plus").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                        .accessibilityLabel("Adicionar cartão em \(column.title)")
                        .help("Adicionar cartão em \(column.title)")
                }
                Text(column.subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondary)
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
                            Text(query.isEmpty ? column.emptyTitle : "Nenhum cartão encontrado")
                                .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                            Text(query.isEmpty ? (column == .doing ? "Trabalhe em até \(store.snapshot.wipLimit) \(store.snapshot.wipLimit == 1 ? "cartão" : "cartões") por vez." : column.emptyHelp) : "Tente buscar outra palavra.")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 40)
                    }
                    Button(action: addCard) {
                        Label("Adicionar cartão", systemImage: "plus").font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    .accessibilityLabel("Novo cartão na coluna \(column.title)")
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
    }
}

private struct StickyCard: View {
    let card: KanbanCard
    let open: () -> Void
    @ObservedObject var store: BoardStore
    @State private var hover = false

    var body: some View {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    RoundedRectangle(cornerRadius: 2).fill(card.color.mark.opacity(0.6)).frame(width: 25, height: 3)
                    Spacer()
                    Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.ink.opacity(0.6))
                }.accessibilityHidden(true)
                Text(card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sem título" : card.title)
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
        .accessibilityLabel("\(card.title.isEmpty ? "Sem título" : card.title), \(card.column.title)")
        .accessibilityHint("Abre o cartão para editar. Também pode ser arrastado para outra coluna.")
        .help("Clique para editar. Arraste para mover. Clique com o botão direito para mais opções.")
        .contextMenu {
            Button("Editar cartão", action: open)
            Menu("Mover para") {
                ForEach(KanbanColumn.allCases.filter { $0 != card.column }, id: \.self) { column in
                    Button(column.title) { _ = store.moveCard(id: card.id, to: column, before: nil) }
                }
            }
            Button("Mover para o início da coluna") {
                _ = store.moveCard(id: card.id, to: card.column, before: store.cards(in: card.column, query: "").first?.id)
            }
            Button("Mover para o fim da coluna") { _ = store.moveCard(id: card.id, to: card.column, before: nil) }
            Divider()
            Button("Excluir cartão", role: .destructive) { _ = store.deleteCard(id: card.id) }
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
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.setFrameAutosaveName("KornucopiaBoard")
            window.backgroundColor = NSColor(red: 244/255, green: 248/255, blue: 247/255, alpha: 1)
        }
    }
}
