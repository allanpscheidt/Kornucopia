import SwiftUI
import AppKit

@MainActor
enum PendingEditorDraft {
    static var text: String?
    static func permitsClosing() -> Bool {
        guard let text else { return true }
        guard closeWithRejectedDraft(text) else { return false }
        self.text = nil
        return true
    }
}

@MainActor
func closeWithRejectedDraft(_ text: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = L("error.unsavedDraft")
    alert.informativeText = L("error.unsavedDraftBody")
    alert.alertStyle = .warning
    alert.addButton(withTitle: L("action.keepOpen"))
    alert.addButton(withTitle: L("action.copyAndClose"))
    guard alert.runModal() == .alertSecondButtonReturn else { return false }
    NSPasteboard.general.clearContents()
    guard NSPasteboard.general.setString(text, forType: .string) else {
        let failure = NSAlert()
        failure.messageText = L("error.copyDraft")
        failure.addButton(withTitle: L("action.understood"))
        failure.runModal()
        return false
    }
    return true
}

struct CardEditor: View {
    @ObservedObject var store: BoardStore
    @ObservedObject private var localization = AppLocalization.shared
    let cardID: UUID
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var showDelete = false
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var rejectedTitle = false
    @State private var rejectedNotes = false

    private var card: KanbanCard? { store.card(id: cardID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let card {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("card.label")).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.strong)
                        Text(L("menu.editCard")).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button { finishEditing() } label: { Image(systemName: "xmark").frame(width: 30, height: 30) }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel(L("a11y.closeCard"))
                }
                .padding(24).background(card.color.paper)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(L("card.title"))
                        TextField(L("card.titlePlaceholder"), text: textBinding(\.title))
                            .font(.system(size: 17, weight: .medium)).textFieldStyle(.plain)
                            .padding(12).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(titleFocused ? Theme.accent : Theme.line, lineWidth: 1))
                            .focused($titleFocused).accessibilityLabel(L("a11y.cardTitle"))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(L("card.notes"))
                        TextEditor(text: textBinding(\.notes))
                            .font(.system(size: 13)).lineSpacing(4).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 180).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                            .accessibilityLabel(L("a11y.cardNotes"))
                    }
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel(L("card.column"))
                            Picker(L("card.column"), selection: Binding(get: { self.card?.column ?? .backlog }, set: { _ = store.updateCard(id: cardID, column: $0) })) {
                                ForEach(KanbanColumn.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 180)
                            .accessibilityLabel(L("a11y.cardColumn"))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel(L("card.color"))
                            HStack(spacing: 8) {
                                Circle().fill(card.color.paper).frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(card.color.mark.opacity(0.6), lineWidth: 1)).accessibilityHidden(true)
                                Text(card.color.title).font(.system(size: 12))
                            }
                            Text(L("card.colorAutomatic")).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                    if rejectedTitle || rejectedNotes {
                        Label(L("storage.editRejected"), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    } else if let error = store.saveError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label(L("card.autosaved"), systemImage: "checkmark.circle")
                            .font(.system(size: 11)).foregroundStyle(Theme.strong)
                    }
                }
                .padding(24)
                Divider()
                HStack {
                    Button { showDelete = true } label: { Label(L("action.deleteCard"), systemImage: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(Color(hex: 0x98483E)).font(.system(size: 12))
                    Spacer()
                    Button { finishEditing() } label: {
                        Text(L("action.done")).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 22).frame(height: 38)
                    }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            } else {
                Text(L("card.removed")).padding(24)
                Button(L("action.close")) { dismiss() }.padding(24)
            }
        }
        .frame(width: 570).background(Color.white).foregroundStyle(Theme.ink).tint(Theme.accent)
        .onAppear {
            PendingEditorDraft.text = nil
            titleDraft = card?.title ?? ""
            notesDraft = card?.notes ?? ""
            titleFocused = true
        }
        .interactiveDismissDisabled(rejectedTitle || rejectedNotes)
        .onChange(of: card?.title) { _, value in
            if !rejectedTitle { titleDraft = value ?? "" }
        }
        .onChange(of: card?.notes) { _, value in
            if !rejectedNotes { notesDraft = value ?? "" }
        }
        .confirmationDialog(L("card.deleteConfirmation"), isPresented: $showDelete, titleVisibility: .visible) {
            Button(L("action.deleteCard"), role: .destructive) { _ = store.deleteCard(id: cardID); PendingEditorDraft.text = nil; dismiss() }
            Button(L("action.cancel"), role: .cancel) {}
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
    }
    private func textBinding(_ key: KeyPath<KanbanCard, String>) -> Binding<String> {
        Binding(get: { key == \KanbanCard.title ? titleDraft : notesDraft }, set: { text in
            if key == \KanbanCard.title {
                titleDraft = text
                rejectedTitle = !store.updateCard(id: cardID, title: text)
            } else {
                notesDraft = text
                rejectedNotes = !store.updateCard(id: cardID, notes: text)
            }
            PendingEditorDraft.text = rejectedTitle || rejectedNotes ? titleDraft + "\n\n" + notesDraft : nil
        })
    }
    private func finishEditing() {
        if rejectedTitle || rejectedNotes {
            guard PendingEditorDraft.permitsClosing() else { return }
            dismiss()
            return
        }
        guard store.updateCard(id: cardID, title: titleDraft, notes: notesDraft) else { return }
        rejectedTitle = false
        rejectedNotes = false
        PendingEditorDraft.text = nil
        dismiss()
    }
}

struct SettingsView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.dismiss) private var dismiss
    @State private var limitText = ""
    @State private var limitError: String?
    @State private var boardTitleDraft = ""

    private var minimum: Int { max(1, store.cards(in: .doing, query: "").count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(L("settings.title")).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.strong)
                Spacer()
                Button { finishSettings() } label: { Image(systemName: "xmark").frame(width: 30, height: 30) }
                    .buttonStyle(.plain).accessibilityLabel(L("a11y.closeSettings"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("settings.boardName")).font(.system(size: 12, weight: .semibold))
                TextField(L("board.defaultTitle"), text: $boardTitleDraft)
                    .textFieldStyle(.roundedBorder).accessibilityLabel(L("settings.boardName"))
                    .onChange(of: boardTitleDraft) { _, title in
                        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            PendingEditorDraft.text = store.setBoardTitle(title) ? nil : title
                        }
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(L("settings.language")).font(.system(size: 12, weight: .semibold))
                Picker(L("settings.language"), selection: Binding(get: { localization.selection }, set: { localization.select($0) })) {
                    Text(L("settings.systemLanguage", ["language": localization.systemLanguage.nativeName]))
                        .tag(AppLocalization.automatic)
                    ForEach(AppLanguage.allCases) { language in
                        Text(L("language." + language.rawValue)).tag(language.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.menu).accessibilityLabel(L("settings.language"))
                Text(L("settings.languageDescription")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(L("settings.wipTitle")).font(.system(size: 17, weight: .bold))
                Text(L("settings.wipDescription"))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Text(L("settings.wipMaximum")).font(.system(size: 13, weight: .medium))
                    Spacer()
                    TextField(L("settings.wipLimit"), text: $limitText)
                        .multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(width: 62)
                        .accessibilityLabel(L("a11y.wipMaximum"))
                        .onChange(of: limitText) { _, value in applyLimit(value) }
                    Stepper(L("settings.wipAdjust"), onIncrement: {
                        if store.snapshot.wipLimit < Int.max { limitText = String(store.snapshot.wipLimit + 1) }
                    }, onDecrement: {
                        limitText = String(max(minimum, store.snapshot.wipLimit - 1))
                    }).labelsHidden().accessibilityLabel(L("a11y.wipAdjust"))
                }.padding(.vertical, 8)
                if let limitError {
                    Text(L(limitError, ["limit": String(minimum)])).font(.system(size: 11)).foregroundStyle(Theme.warning)
                }
                Label(L("settings.wipTip"), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.strong).fixedSize(horizontal: false, vertical: true)
                    .padding(16).background(Theme.column, in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            Text(L("settings.storageLimits"))
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(store.saveError == nil ? L("board.autosaved") : L("board.saveFailed"), systemImage: store.saveError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(store.saveError == nil ? Theme.secondary : Theme.warning)
                Spacer()
                Button { finishSettings() } label: {
                    Text(L("action.done")).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 22).frame(height: 38)
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 570).background(Color.white).foregroundStyle(Theme.ink).tint(Theme.accent)
        .onAppear { limitText = String(store.snapshot.wipLimit); boardTitleDraft = store.snapshot.boardTitle }
        .onChange(of: store.snapshot.boardTitle) { _, title in
            if boardTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines) != title { boardTitleDraft = title }
        }
        .onChange(of: store.snapshot.wipLimit) { _, limit in
            if Int(limitText) != limit { limitText = String(limit) }
        }
        .onDisappear { _ = store.setBoardTitle(boardTitleDraft) }
        .interactiveDismissDisabled(boardTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines) != store.snapshot.boardTitle && !boardTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func finishSettings() {
        guard store.setBoardTitle(boardTitleDraft) else {
            PendingEditorDraft.text = boardTitleDraft
            if PendingEditorDraft.permitsClosing() { dismiss() }
            return
        }
        limitText = String(store.snapshot.wipLimit)
        PendingEditorDraft.text = nil
        dismiss()
    }

    private func applyLimit(_ value: String) {
        guard let limit = Int(value), limit >= minimum else {
            limitError = "settings.invalidLimit"
            return
        }
        guard store.setWIPLimit(limit) else { limitError = "settings.wipUpdateError"; return }
        limitError = nil
    }
}
