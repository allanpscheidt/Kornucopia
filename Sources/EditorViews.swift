import SwiftUI

struct CardEditor: View {
    @ObservedObject var store: BoardStore
    let cardID: UUID
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var showDelete = false

    private var card: KanbanCard? { store.card(id: cardID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let card {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("CARTÃO").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.strong)
                        Text("Editar cartão").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 30, height: 30) }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Fechar cartão")
                }
                .padding(24).background(card.color.paper)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Título")
                        TextField("Nome da ideia ou tarefa", text: textBinding(\.title))
                            .font(.system(size: 17, weight: .medium)).textFieldStyle(.plain)
                            .padding(12).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(titleFocused ? Theme.accent : Theme.line, lineWidth: 1))
                            .focused($titleFocused).accessibilityLabel("Título do cartão")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Anotações")
                        TextEditor(text: textBinding(\.notes))
                            .font(.system(size: 13)).lineSpacing(4).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 180).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                            .accessibilityLabel("Anotações do cartão")
                    }
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Coluna")
                            Picker("Coluna", selection: Binding(get: { self.card?.column ?? .backlog }, set: { _ = store.updateCard(id: cardID, column: $0) })) {
                                ForEach(KanbanColumn.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 180)
                            .accessibilityLabel("Coluna do cartão")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Cor da coluna")
                            HStack(spacing: 8) {
                                Circle().fill(card.color.paper).frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(card.color.mark.opacity(0.6), lineWidth: 1)).accessibilityHidden(true)
                                Text(card.color.title).font(.system(size: 12))
                            }
                            Text("A cor acompanha a coluna.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                    if let error = store.saveError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("Alterações salvas automaticamente", systemImage: "checkmark.circle")
                            .font(.system(size: 11)).foregroundStyle(Theme.strong)
                    }
                }
                .padding(24)
                Divider()
                HStack {
                    Button { showDelete = true } label: { Label("Excluir cartão", systemImage: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(Color(hex: 0x98483E)).font(.system(size: 12))
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Concluído").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 22).frame(height: 38)
                    }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            } else {
                Text("Este cartão foi removido do quadro.").padding(24)
                Button("Fechar") { dismiss() }.padding(24)
            }
        }
        .frame(width: 570).background(Color.white).foregroundStyle(Theme.ink).tint(Theme.accent)
        .onAppear { titleFocused = true }
        .confirmationDialog("Excluir este cartão? Você pode recuperar com Desfazer (⌘Z).", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Excluir cartão", role: .destructive) { _ = store.deleteCard(id: cardID); dismiss() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
    }
    private func textBinding(_ key: KeyPath<KanbanCard, String>) -> Binding<String> {
        Binding(get: { card?[keyPath: key] ?? "" }, set: { text in
            if key == \KanbanCard.title { _ = store.updateCard(id: cardID, title: text) }
            else { _ = store.updateCard(id: cardID, notes: text) }
        })
    }
}

struct SettingsView: View {
    @ObservedObject var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var limitText = ""
    @State private var limitError: String?
    @State private var boardTitleDraft = ""

    private var minimum: Int { max(1, store.cards(in: .doing, query: "").count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Configurações").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.strong)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 30, height: 30) }
                    .buttonStyle(.plain).accessibilityLabel("Fechar configurações")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Nome do quadro").font(.system(size: 12, weight: .semibold))
                TextField("Meu quadro", text: $boardTitleDraft)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Nome do quadro")
                    .onChange(of: boardTitleDraft) { _, title in
                        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { _ = store.setBoardTitle(title) }
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Limites de WIP").font(.system(size: 17, weight: .bold))
                Text("WIP significa trabalho em progresso. Escolha quantos cartões podem ficar em Fazendo ao mesmo tempo.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Text("Máximo em Fazendo").font(.system(size: 13, weight: .medium))
                    Spacer()
                    TextField("Limite", text: $limitText)
                        .multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(width: 62)
                        .accessibilityLabel("Número máximo de cartões em Fazendo")
                        .onChange(of: limitText) { _, value in applyLimit(value) }
                    Stepper("Ajustar limite", onIncrement: {
                        if store.snapshot.wipLimit < Int.max { limitText = String(store.snapshot.wipLimit + 1) }
                    }, onDecrement: {
                        limitText = String(max(minimum, store.snapshot.wipLimit - 1))
                    }).labelsHidden().accessibilityLabel("Aumentar ou reduzir limite de WIP")
                }.padding(.vertical, 8)
                if let limitError {
                    Text(limitError).font(.system(size: 11)).foregroundStyle(Theme.warning)
                }
                Label("Ao atingir o limite, conclua um cartão e mova-o para Revisão. Novas ideias ficam no Backlog.", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.strong).fixedSize(horizontal: false, vertical: true)
                    .padding(16).background(Theme.column, in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            HStack {
                Label(store.saveError == nil ? "Salvo automaticamente no Mac" : "Falha ao salvar", systemImage: store.saveError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(store.saveError == nil ? Theme.secondary : Theme.warning)
                Spacer()
                Button { limitText = String(store.snapshot.wipLimit); dismiss() } label: {
                    Text("Concluído").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 22).frame(height: 38)
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 520).background(Color.white).foregroundStyle(Theme.ink).tint(Theme.accent)
        .onAppear { limitText = String(store.snapshot.wipLimit); boardTitleDraft = store.snapshot.boardTitle }
        .onChange(of: store.snapshot.boardTitle) { _, title in
            if boardTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines) != title { boardTitleDraft = title }
        }
        .onChange(of: store.snapshot.wipLimit) { _, limit in
            if Int(limitText) != limit { limitText = String(limit) }
        }
        .onDisappear { _ = store.setBoardTitle(boardTitleDraft) }
    }

    private func applyLimit(_ value: String) {
        guard let limit = Int(value), limit >= minimum else {
            limitError = "Use um número inteiro a partir de \(minimum). O limite deve acomodar os cartões atuais."
            return
        }
        guard store.setWIPLimit(limit) else { limitError = "Não foi possível alterar o limite."; return }
        limitError = nil
    }
}
