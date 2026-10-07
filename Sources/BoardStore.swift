import Combine
import Foundation

enum KanbanColumn: String, Codable, CaseIterable, Identifiable {
    case backlog, doing, review, done

    var id: String { rawValue }

    @MainActor var title: String { L("column." + rawValue + ".title") }
    @MainActor var subtitle: String { L("column." + rawValue + ".subtitle") }

    var noteColor: NoteColor {
        switch self {
        case .backlog: return .yellow
        case .doing: return .blue
        case .review: return .purple
        case .done: return .green
        }
    }
}

enum NoteColor: String, Codable, CaseIterable, Identifiable {
    case yellow, blue, purple, green, rose

    var id: String { rawValue }

    @MainActor var title: String { L("color." + rawValue) }

}

struct KanbanCard: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var column: KanbanColumn
    var color: NoteColor
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        notes: String = "",
        column: KanbanColumn = .backlog,
        color: NoteColor = .yellow,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.column = column
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

struct BoardSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var cards: [KanbanCard]
    var boardTitle: String
    var wipLimit: Int

    init(schemaVersion: Int = 1, cards: [KanbanCard] = [], boardTitle: String = "Meu quadro", wipLimit: Int = 2) {
        self.schemaVersion = schemaVersion
        self.cards = cards
        self.boardTitle = boardTitle
        self.wipLimit = wipLimit
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, cards, boardTitle, wipLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        cards = try container.decode([KanbanCard].self, forKey: .cards)
        boardTitle = try container.decode(String.self, forKey: .boardTitle)
        wipLimit = try container.decodeIfPresent(Int.self, forKey: .wipLimit) ?? 2
    }
}

/// A card's position in `cards` is its order within its column after filtering.
/// Mutations stay in memory if writing fails; `saveError` exposes that failure.
@MainActor
final class BoardStore: ObservableObject {
    @Published private(set) var snapshot: BoardSnapshot
    @Published private(set) var saveError: String?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var lastSaved: Date?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var wipAlert = false

    let dataDirectory: URL
    var documentURL: URL { dataDirectory.appendingPathComponent("board.json") }
    var backupURL: URL { dataDirectory.appendingPathComponent("board.backup.json") }
    var wipLimit: Int { snapshot.wipLimit }

    private let fileManager = FileManager.default
    private let historyLimit = 100
    private let textEditInterval: TimeInterval = 0.7
    private var undoStack: [BoardSnapshot] = []
    private var redoStack: [BoardSnapshot] = []
    private var writesBlockedKey: String?
    private var writesBlockedDetail = ""
    private var saveErrorKey: String?
    private var saveErrorDetail = ""
    private var recoveryKey: String?
    private var languageSubscription: AnyCancellable?
    private var lastTextEditCardID: UUID?
    private var lastTextEditUptime: TimeInterval = 0

    init(directory: URL? = nil) {
        if let directory {
            dataDirectory = directory
        } else if let path = ProcessInfo.processInfo.environment["KORNUCOPIA_DATA_DIR"], !path.isEmpty {
            dataDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else if let path = ProcessInfo.processInfo.environment["KANBAN_DATA_DIR"], !path.isEmpty {
            dataDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dataDirectory = support.appendingPathComponent("Kornucopia", isDirectory: true)
        }
        snapshot = BoardSnapshot(boardTitle: L("board.defaultTitle"))
        load()
        languageSubscription = AppLocalization.shared.$language.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshLocalizedMessages() }
        }
    }

    func card(id: UUID) -> KanbanCard? {
        snapshot.cards.first { $0.id == id }
    }

    func cards(in column: KanbanColumn, query: String = "") -> [KanbanCard] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.cards.filter { card in
            card.column == column && (search.isEmpty ||
                card.title.localizedStandardContains(search) ||
                card.notes.localizedStandardContains(search))
        }
    }

    @discardableResult
    func createCard(in column: KanbanColumn = .backlog, color: NoteColor = .yellow) -> UUID? {
        guard permits(column: column, currentColumn: nil) else { return nil }
        let card = KanbanCard(column: column, color: column.noteColor)
        var next = snapshot
        next.cards.append(card)
        commit(next)
        return card.id
    }

    /// Returns whether the edit was accepted. A disk error is reported separately.
    @discardableResult
    func updateCard(
        id: UUID,
        title: String? = nil,
        notes: String? = nil,
        column: KanbanColumn? = nil,
        color: NoteColor? = nil
    ) -> Bool {
        guard let index = snapshot.cards.firstIndex(where: { $0.id == id }) else { return false }
        let current = snapshot.cards[index]
        let destination = column ?? current.column
        guard permits(column: destination, currentColumn: current.column) else { return false }
        var next = snapshot
        if let title { next.cards[index].title = title }
        if let notes { next.cards[index].notes = notes }
        next.cards[index].color = destination.noteColor
        next.cards[index].column = destination
        guard next != snapshot else { return true }
        next.cards[index].updatedAt = Date()
        let isTextEdit = column == nil && color == nil && (title != nil || notes != nil)
        commit(next, coalescingCardID: isTextEdit ? id : nil)
        return true
    }

    /// Moves before a card in the destination column, or to that column's end.
    @discardableResult
    func moveCard(id: UUID, to column: KanbanColumn, before targetID: UUID? = nil) -> Bool {
        guard let sourceIndex = snapshot.cards.firstIndex(where: { $0.id == id }) else { return false }
        let current = snapshot.cards[sourceIndex]
        guard permits(column: column, currentColumn: current.column) else { return false }
        if targetID == id { return current.column == column }
        if let targetID {
            guard let target = card(id: targetID), target.column == column else { return false }
        }

        var next = snapshot
        var movingCard = next.cards.remove(at: sourceIndex)
        movingCard.column = column
        movingCard.color = column.noteColor
        let insertionIndex: Int
        if let targetID, let targetIndex = next.cards.firstIndex(where: { $0.id == targetID }) {
            insertionIndex = targetIndex
        } else if let last = next.cards.lastIndex(where: { $0.column == column }) {
            insertionIndex = last + 1
        } else {
            insertionIndex = next.cards.endIndex
        }
        next.cards.insert(movingCard, at: insertionIndex)
        guard next != snapshot else { return true }
        next.cards[insertionIndex].updatedAt = Date()
        commit(next)
        return true
    }

    @discardableResult
    func deleteCard(id: UUID) -> Bool {
        guard let index = snapshot.cards.firstIndex(where: { $0.id == id }) else { return false }
        var next = snapshot
        next.cards.remove(at: index)
        commit(next)
        return true
    }

    @discardableResult
    func setBoardTitle(_ title: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = snapshot
        next.boardTitle = value.isEmpty ? L("board.defaultTitle") : value
        guard next != snapshot else { return true }
        commit(next)
        return true
    }

    @discardableResult
    func setWIPLimit(_ limit: Int) -> Bool {
        guard limit >= 1, limit >= snapshot.cards.lazy.filter({ $0.column == .doing }).count else { return false }
        guard limit != snapshot.wipLimit else { return true }
        var next = snapshot
        next.wipLimit = limit
        commit(next)
        return true
    }

    @discardableResult
    func undo() -> Bool {
        resetTextEditGrouping()
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(snapshot)
        trimHistory(&redoStack)
        snapshot = previous
        updateHistoryAvailability()
        flush()
        return true
    }

    @discardableResult
    func redo() -> Bool {
        resetTextEditGrouping()
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(snapshot)
        trimHistory(&undoStack)
        snapshot = next
        updateHistoryAvailability()
        flush()
        return true
    }

    /// Saves a full snapshot atomically and preserves the previous valid JSON.
    @discardableResult
    func flush() -> Bool {
        if let writesBlockedKey {
            setSaveError(writesBlockedKey, detail: writesBlockedDetail)
            return false
        }
        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)

            if fileManager.fileExists(atPath: documentURL.path) {
                let previousData = try Data(contentsOf: documentURL)
                do {
                    _ = try decode(previousData)
                } catch {
                    try preserveUnreadableFile(at: documentURL)
                    setRecovery("recovery.previous")
                }
                if fileManager.fileExists(atPath: documentURL.path) {
                    if fileManager.fileExists(atPath: backupURL.path) {
                        let existingBackup = try Data(contentsOf: backupURL)
                        do {
                            _ = try decode(existingBackup)
                        } catch {
                            try preserveUnreadableFile(at: backupURL)
                            setRecovery("recovery.backupPrevious")
                        }
                    }
                    try previousData.write(to: backupURL, options: .atomic)
                }
            }
            try data.write(to: documentURL, options: .atomic)
            lastSaved = Date()
            saveError = nil
            saveErrorKey = nil
            return true
        } catch {
            setSaveError("error.save", detail: localizedDetail(error))
            return false
        }
    }

    private func permits(column: KanbanColumn, currentColumn: KanbanColumn?) -> Bool {
        if column == .doing && currentColumn != .doing &&
            snapshot.cards.lazy.filter({ $0.column == .doing }).count >= snapshot.wipLimit {
            wipAlert = true
            return false
        }
        return true
    }

    private func commit(_ next: BoardSnapshot, coalescingCardID: UUID? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        let continuesTextEdit = coalescingCardID != nil &&
            coalescingCardID == lastTextEditCardID &&
            now - lastTextEditUptime <= textEditInterval && redoStack.isEmpty
        if !continuesTextEdit {
            undoStack.append(snapshot)
            trimHistory(&undoStack)
        }
        redoStack.removeAll()
        snapshot = next
        lastTextEditCardID = coalescingCardID
        lastTextEditUptime = coalescingCardID == nil ? 0 : now
        updateHistoryAvailability()
        flush()
    }

    private func trimHistory(_ stack: inout [BoardSnapshot]) {
        if stack.count > historyLimit {
            stack.removeFirst(stack.count - historyLimit)
        }
    }

    private func resetTextEditGrouping() {
        lastTextEditCardID = nil
        lastTextEditUptime = 0
    }

    private func updateHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func decode(_ data: Data) throws -> BoardSnapshot {
        var decoded = try JSONDecoder().decode(BoardSnapshot.self, from: data)
        guard decoded.schemaVersion == 1 else { throw StorageError.unsupportedVersion }
        guard decoded.wipLimit >= 1 else { throw StorageError.invalidWIPLimit }
        guard Set(decoded.cards.map(\.id)).count == decoded.cards.count else {
            throw StorageError.duplicateIdentifiers
        }
        for index in decoded.cards.indices {
            decoded.cards[index].color = decoded.cards[index].column.noteColor
        }
        return decoded
    }

    private func load() {
        var unreadable = false
        if fileManager.fileExists(atPath: documentURL.path) {
            do {
                snapshot = try decode(Data(contentsOf: documentURL))
                lastSaved = (try? fileManager.attributesOfItem(atPath: documentURL.path)[.modificationDate]) as? Date
                return
            } catch {
                unreadable = true
                do {
                    try preserveUnreadableFile(at: documentURL)
                } catch {
                    writesBlockedKey = "error.preservePrimary"
                    writesBlockedDetail = localizedDetail(error)
                    setSaveError("error.preservePrimary", detail: writesBlockedDetail)
                }
            }
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            do {
                snapshot = try decode(Data(contentsOf: backupURL))
                setRecovery("recovery.backupRecovered")
                return
            } catch {
                unreadable = true
                do {
                    try preserveUnreadableFile(at: backupURL)
                } catch {
                    writesBlockedKey = "error.preserveBackup"
                    writesBlockedDetail = localizedDetail(error)
                    setSaveError("error.preserveBackup", detail: writesBlockedDetail)
                }
            }
        }
        if unreadable {
            setRecovery("recovery.unreadable")
        }
    }

    private func preserveUnreadableFile(at url: URL) throws {
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let preserved = dataDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).corrupt-\(stamp)-\(UUID().uuidString).json")
        try fileManager.moveItem(at: url, to: preserved)
    }

    private func setSaveError(_ key: String, detail: String) {
        saveErrorKey = key
        saveErrorDetail = detail
        saveError = L(key, ["detail": detail])
    }

    private func setRecovery(_ key: String) {
        recoveryKey = key
        recoveryMessage = L(key)
    }

    private func refreshLocalizedMessages() {
        if let saveErrorKey { saveError = L(saveErrorKey, ["detail": saveErrorDetail]) }
        if let recoveryKey { recoveryMessage = L(recoveryKey) }
    }

    private func localizedDetail(_ error: Error) -> String {
        guard let storageError = error as? StorageError else { return error.localizedDescription }
        switch storageError {
        case .unsupportedVersion: return L("error.unsupportedVersion")
        case .duplicateIdentifiers: return L("error.duplicateIdentifiers")
        case .invalidWIPLimit: return L("error.invalidWIPLimit")
        }
    }

    private enum StorageError: Error {
        case unsupportedVersion, duplicateIdentifiers, invalidWIPLimit
    }
}
