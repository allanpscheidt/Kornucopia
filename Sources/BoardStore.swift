import Combine
import CryptoKit
import Darwin
import Foundation

// membership.h is not exposed by the Darwin Swift module. This public libc
// function identifies an ACL user without resolving a path or a group name.
@_silgen_name("mbr_uid_to_uuid")
private func membershipUserUUID(_ uid: uid_t, _ uuid: UnsafeMutablePointer<UInt8>) -> Int32

/// Shared with Windows. Text budgets measure decoded UTF-8, never character counts.
enum BoardStorageLimits {
    static let fileBytes = 16 * 1_024 * 1_024
    static let cards = 10_000
    static let boardTitleBytes = 1_024
    static let cardTitleBytes = 4_096
    static let cardNotesBytes = 262_144
    static let totalTextBytes = 8 * 1_024 * 1_024
    static let jsonDepth = 32
    static let jsonTokens = 250_000

    static func validate(_ snapshot: BoardSnapshot) throws {
        guard snapshot.cards.count <= cards else { throw StorageError.cardCount }
        guard snapshot.boardTitle.utf8.count <= boardTitleBytes else { throw StorageError.fieldSize }
        var total = snapshot.boardTitle.utf8.count
        for card in snapshot.cards {
            try validate(card, total: &total)
        }
    }

    static func validate(_ card: KanbanCard, total: inout Int) throws {
        let titleBytes = card.title.utf8.count
        let notesBytes = card.notes.utf8.count
        guard titleBytes <= cardTitleBytes, notesBytes <= cardNotesBytes else { throw StorageError.fieldSize }
        guard titleBytes <= totalTextBytes - total,
              notesBytes <= totalTextBytes - total - titleBytes else { throw StorageError.textBudget }
        total += titleBytes + notesBytes
    }
}

private enum StorageError: Error, Equatable {
    case unsupportedVersion, duplicateIdentifiers, invalidWIPLimit
    case fileType, fileSize, cardCount, fieldSize, textBudget
    case structure, changed, unsafeRoot
}

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
        boardTitle = try container.decode(String.self, forKey: .boardTitle)
        guard boardTitle.utf8.count <= BoardStorageLimits.boardTitleBytes else { throw StorageError.fieldSize }
        var cardContainer = try container.nestedUnkeyedContainer(forKey: .cards)
        if let count = cardContainer.count, count > BoardStorageLimits.cards { throw StorageError.cardCount }
        cards = []
        cards.reserveCapacity(min(cardContainer.count ?? 0, BoardStorageLimits.cards))
        var total = boardTitle.utf8.count
        while !cardContainer.isAtEnd {
            guard cards.count < BoardStorageLimits.cards else { throw StorageError.cardCount }
            let card = try cardContainer.decode(KanbanCard.self)
            try BoardStorageLimits.validate(card, total: &total)
            cards.append(card)
        }
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
    @Published var storageAlert: String?

    let dataDirectory: URL
    var documentURL: URL { dataDirectory.appendingPathComponent("board.json") }
    var backupURL: URL { dataDirectory.appendingPathComponent("board.backup.json") }
    var wipLimit: Int { snapshot.wipLimit }
    var recoveryTitleKey: String {
        recoveryKey == "recovery.unsafeRoot" || recoveryKey == "recovery.permissionsUpdated"
            ? "storage.alertTitle" : "recovery.title"
    }

    private let isDefaultDataDirectory: Bool
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
    private var expectedPrimaryDigest: Data?
    private var expectedBackupDigest: Data?
    private var lastRejectedStorageKey: String?
    private var pinnedDirectories: [PinnedDirectory] = []
    private var rootPath: String {
        // Foundation's standardizedFileURL can rewrite /private/tmp to the
        // symlink /tmp. Only remove lexical ./ components; never resolve aliases.
        let parts = dataDirectory.path.split(separator: "/").filter { $0 != "." }
        return "/" + parts.joined(separator: "/")
    }

    init(directory: URL? = nil) {
        if let directory {
            dataDirectory = directory
            isDefaultDataDirectory = false
        } else if let path = ProcessInfo.processInfo.environment["KORNUCOPIA_DATA_DIR"], !path.isEmpty {
            dataDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            isDefaultDataDirectory = false
        } else if let path = ProcessInfo.processInfo.environment["KANBAN_DATA_DIR"], !path.isEmpty {
            dataDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            isDefaultDataDirectory = false
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dataDirectory = support.appendingPathComponent("Kornucopia", isDirectory: true)
            isDefaultDataDirectory = true
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
        guard commit(next) else { return nil }
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
        guard next != snapshot else { return acceptUnchanged() }
        next.cards[index].updatedAt = Date()
        let isTextEdit = column == nil && color == nil && (title != nil || notes != nil)
        return commit(next, coalescingCardID: isTextEdit ? id : nil)
    }

    /// Moves before a card in the destination column, or to that column's end.
    @discardableResult
    func moveCard(id: UUID, to column: KanbanColumn, before targetID: UUID? = nil) -> Bool {
        guard let sourceIndex = snapshot.cards.firstIndex(where: { $0.id == id }) else { return false }
        let current = snapshot.cards[sourceIndex]
        guard permits(column: column, currentColumn: current.column) else { return false }
        if targetID == id { return current.column == column ? acceptUnchanged() : false }
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
        guard next != snapshot else { return acceptUnchanged() }
        next.cards[insertionIndex].updatedAt = Date()
        return commit(next)
    }

    @discardableResult
    func deleteCard(id: UUID) -> Bool {
        guard let index = snapshot.cards.firstIndex(where: { $0.id == id }) else { return false }
        var next = snapshot
        next.cards.remove(at: index)
        return commit(next)
    }

    @discardableResult
    func setBoardTitle(_ title: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = snapshot
        next.boardTitle = value.isEmpty ? L("board.defaultTitle") : value
        guard next != snapshot else { return acceptUnchanged() }
        return commit(next)
    }

    @discardableResult
    func setWIPLimit(_ limit: Int) -> Bool {
        guard limit >= 1, limit >= snapshot.cards.lazy.filter({ $0.column == .doing }).count else { return false }
        guard limit != snapshot.wipLimit else { return acceptUnchanged() }
        var next = snapshot
        next.wipLimit = limit
        return commit(next)
    }

    @discardableResult
    func undo() -> Bool {
        resetTextEditGrouping()
        guard let previous = undoStack.popLast() else { return false }
        lastRejectedStorageKey = nil
        storageAlert = nil
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
        lastRejectedStorageKey = nil
        storageAlert = nil
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
        flush(preencoded: nil)
    }

    private func encodedSnapshot(_ snapshot: BoardSnapshot) throws -> Data {
        try BoardStorageLimits.validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= BoardStorageLimits.fileBytes else { throw StorageError.fileSize }
        return data
    }

    @discardableResult
    private func flush(preencoded: Data?) -> Bool {
        if let writesBlockedKey {
            setSaveError(writesBlockedKey, detail: writesBlockedDetail)
            return false
        }
        do {
            let data = try preencoded ?? encodedSnapshot(snapshot)
            guard let directoryFD = try openDataDirectory(createIfMissing: true) else { throw StorageError.fileType }
            defer { close(directoryFD) }
            var previousData: Data?
            var primaryIdentity: FileIdentity?
            var backupIdentity: FileIdentity?
            if try entryExists(at: documentURL, directoryFD: directoryFD) {
                let identity = try fileIdentity(at: documentURL, directoryFD: directoryFD)
                do {
                    let existing = try readBoardFile(at: documentURL, directoryFD: directoryFD)
                    if digest(existing.data) != expectedPrimaryDigest {
                        _ = try decode(existing.data)
                        throw StorageError.changed
                    }
                    previousData = existing.data
                    primaryIdentity = existing.identity
                } catch {
                    if error as? StorageError == .changed || error as? StorageError == .unsafeRoot { throw error }
                    try preserveUnreadableFile(at: documentURL, expected: identity, directoryFD: directoryFD)
                    expectedPrimaryDigest = nil
                    setRecovery("recovery.previous")
                }
            } else if expectedPrimaryDigest != nil {
                throw StorageError.changed
            }
            if try entryExists(at: backupURL, directoryFD: directoryFD) {
                let identity = try fileIdentity(at: backupURL, directoryFD: directoryFD)
                do {
                    let file = try readBoardFile(at: backupURL, directoryFD: directoryFD)
                    if digest(file.data) != expectedBackupDigest {
                        _ = try decode(file.data)
                        throw StorageError.changed
                    }
                    backupIdentity = file.identity
                } catch {
                    if error as? StorageError == .changed || error as? StorageError == .unsafeRoot { throw error }
                    try preserveUnreadableFile(at: backupURL, expected: identity, directoryFD: directoryFD)
                    expectedBackupDigest = nil
                    setRecovery("recovery.backupPrevious")
                }
            } else if expectedBackupDigest != nil {
                throw StorageError.changed
            }
            if let previousData {
                try atomicWrite(previousData, to: backupURL, expected: backupIdentity, directoryFD: directoryFD)
                expectedBackupDigest = digest(previousData)
            }
            try atomicWrite(data, to: documentURL, expected: primaryIdentity, directoryFD: directoryFD)
            expectedPrimaryDigest = digest(data)
            lastSaved = Date()
            saveError = nil
            saveErrorKey = nil
            return true
        } catch {
            setSaveError("error.save", detail: localizedDetail(error))
            if error as? StorageError == .unsafeRoot { setRecovery("recovery.unsafeRoot") }
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

    private func commit(_ next: BoardSnapshot, coalescingCardID: UUID? = nil) -> Bool {
        let data: Data
        do { data = try encodedSnapshot(next) }
        catch {
            let key = (error as? StorageError).map(storageErrorKey) ?? "error.storageStructure"
            if lastRejectedStorageKey != key { storageAlert = key }
            lastRejectedStorageKey = key
            return false
        }
        lastRejectedStorageKey = nil
        storageAlert = nil
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
        flush(preencoded: data)
        return true
    }

    private func acceptUnchanged() -> Bool {
        lastRejectedStorageKey = nil
        storageAlert = nil
        return true
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
        guard data.count <= BoardStorageLimits.fileBytes else { throw StorageError.fileSize }
        try validateJSONStructure(data)
        var decoded = try JSONDecoder().decode(BoardSnapshot.self, from: data)
        guard decoded.schemaVersion == 1 else { throw StorageError.unsupportedVersion }
        guard decoded.wipLimit >= 1 else { throw StorageError.invalidWIPLimit }
        guard Set(decoded.cards.map(\.id)).count == decoded.cards.count else {
            throw StorageError.duplicateIdentifiers
        }
        try BoardStorageLimits.validate(decoded)
        for index in decoded.cards.indices {
            decoded.cards[index].color = decoded.cards[index].column.noteColor
        }
        return decoded
    }

    private func load() {
        do {
            guard let directoryFD = try openDataDirectory(createIfMissing: false) else { return }
            defer { close(directoryFD) }
            try load(directoryFD: directoryFD)
        } catch {
            // An interrupted initial load never establishes ownership of bytes
            // that were read but not installed as this session's snapshot.
            expectedPrimaryDigest = nil
            expectedBackupDigest = nil
            lastSaved = nil
            setSaveError("error.save", detail: localizedDetail(error))
            if error as? StorageError == .unsafeRoot { setRecovery("recovery.unsafeRoot") }
        }
    }

    private func load(directoryFD: Int32) throws {
        var unreadable = false
        var primary: BoardSnapshot?
        var backup: BoardSnapshot?
        var rejectedBackup = false
        if try entryExists(at: documentURL, directoryFD: directoryFD) {
            let identity = try? fileIdentity(at: documentURL, directoryFD: directoryFD)
            do {
                let file = try readBoardFile(at: documentURL, directoryFD: directoryFD)
                primary = try decode(file.data)
                expectedPrimaryDigest = digest(file.data)
                lastSaved = Date(timeIntervalSince1970: TimeInterval(file.identity.modifiedSeconds) + TimeInterval(file.identity.modifiedNanoseconds) / 1_000_000_000)
            } catch {
                if error as? StorageError == .unsafeRoot { throw error }
                unreadable = true
                do {
                    if error as? StorageError == .changed { throw error }
                    try preserveUnreadableFile(at: documentURL, expected: identity, directoryFD: directoryFD)
                } catch {
                    writesBlockedKey = "error.preservePrimary"
                    writesBlockedDetail = localizedDetail(error)
                    setSaveError("error.preservePrimary", detail: writesBlockedDetail)
                }
            }
        }

        if try entryExists(at: backupURL, directoryFD: directoryFD) {
            let identity = try? fileIdentity(at: backupURL, directoryFD: directoryFD)
            do {
                let data = try readBoardFile(at: backupURL, directoryFD: directoryFD).data
                backup = try decode(data)
                expectedBackupDigest = digest(data)
            } catch {
                if error as? StorageError == .unsafeRoot { throw error }
                unreadable = true
                rejectedBackup = true
                do {
                    if error as? StorageError == .changed { throw error }
                    try preserveUnreadableFile(at: backupURL, expected: identity, directoryFD: directoryFD)
                } catch {
                    writesBlockedKey = "error.preserveBackup"
                    writesBlockedDetail = localizedDetail(error)
                    setSaveError("error.preserveBackup", detail: writesBlockedDetail)
                }
            }
        }
        if let primary {
            snapshot = primary
            if rejectedBackup { setRecovery("recovery.backupPrevious") }
            return
        }
        if let backup {
            snapshot = backup
            setRecovery("recovery.backupRecovered")
            return
        }
        if unreadable {
            setRecovery("recovery.unreadable")
        }
    }

    /// lstat includes dangling symlinks, which fileExists would silently ignore.
    private func entryExists(at url: URL, directoryFD: Int32) throws -> Bool {
        try validateRoot(directoryFD)
        var metadata = stat()
        if fstatat(directoryFD, try reservedName(for: url), &metadata, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        if errno == ENOENT { return false }
        throw posixError()
    }

    private struct RootIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        init(_ value: stat) { device = value.st_dev; inode = value.st_ino }
    }

    /// Descriptors keep each ancestor fixed. Every component is opened relative
    /// to its verified parent, so neither parent links nor later swaps redirect IO.
    private final class PinnedDirectory {
        let descriptor: Int32
        let name: String
        let identity: RootIdentity
        var securityStamp: FileIdentity?

        init(descriptor: Int32, name: String, metadata: stat) {
            self.descriptor = descriptor
            self.name = name
            identity = RootIdentity(metadata)
        }

        deinit { close(descriptor) }
    }

    private func openDataDirectory(createIfMissing: Bool) throws -> Int32? {
        if let root = pinnedDirectories.last {
            try validateRoot(root.descriptor)
            let duplicate = fcntl(root.descriptor, F_DUPFD_CLOEXEC, 0)
            guard duplicate >= 0 else { throw posixError() }
            return duplicate
        }

        let components = rootPath.split(separator: "/").map(String.init)
        guard rootPath.hasPrefix("/"), !components.isEmpty,
              !components.contains("."), !components.contains("..") else { throw StorageError.unsafeRoot }
        var chain: [PinnedDirectory] = []
        let filesystemFD = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard filesystemFD >= 0 else { throw posixError() }
        var metadata = stat()
        guard fstat(filesystemFD, &metadata) == 0 else { close(filesystemFD); throw posixError() }
        chain.append(PinnedDirectory(descriptor: filesystemFD, name: "/", metadata: metadata))
        try Self.validateDirectory(filesystemFD, metadata: metadata, isRoot: false)

        for (index, component) in components.enumerated() {
            let parent = chain.last!
            try validateChain(chain, rootIsFinal: false)
            var pathMetadata = stat()
            if fstatat(parent.descriptor, component, &pathMetadata, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw posixError() }
                guard createIfMissing else { return nil }
                if mkdirat(parent.descriptor, component, 0o700) != 0 && errno != EEXIST { throw posixError() }
                guard fstatat(parent.descriptor, component, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
            }
            guard pathMetadata.st_mode & S_IFMT == S_IFDIR else { throw StorageError.unsafeRoot }
            let descriptor = openat(parent.descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                if errno == ELOOP || errno == ENOTDIR || errno == EACCES { throw StorageError.unsafeRoot }
                throw posixError()
            }
            guard fstat(descriptor, &metadata) == 0 else { close(descriptor); throw posixError() }
            let node = PinnedDirectory(descriptor: descriptor, name: component, metadata: metadata)
            chain.append(node)
            guard RootIdentity(metadata) == RootIdentity(pathMetadata) else { throw StorageError.changed }
            let isRoot = index == components.count - 1
            if isRoot && isDefaultDataDirectory && metadata.st_mode & 0o7777 == 0o755 {
                try validateChain(chain, rootIsFinal: false)
                if try Self.tightenLegacyDefaultPermissions(descriptor: descriptor) {
                    setRecovery("recovery.permissionsUpdated")
                    guard fstat(descriptor, &metadata) == 0 else { throw posixError() }
                }
            }
            try Self.validateDirectory(descriptor, metadata: metadata, isRoot: isRoot)
            node.securityStamp = FileIdentity(metadata)
        }
        try validateChain(chain, rootIsFinal: true)
        pinnedDirectories = chain
        let duplicate = fcntl(chain.last!.descriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else { throw posixError() }
        return duplicate
    }

    private func validateChain(_ chain: [PinnedDirectory], rootIsFinal: Bool) throws {
        for (index, node) in chain.enumerated() {
            var metadata = stat()
            guard fstat(node.descriptor, &metadata) == 0 else { throw posixError() }
            guard RootIdentity(metadata) == node.identity else { throw StorageError.changed }
            if index > 0 {
                var pathMetadata = stat()
                guard fstatat(chain[index - 1].descriptor, node.name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
                      pathMetadata.st_mode & S_IFMT == S_IFDIR,
                      RootIdentity(pathMetadata) == node.identity else { throw StorageError.changed }
            }
            let stamp = FileIdentity(metadata)
            if node.securityStamp != stamp {
                try Self.validateDirectory(node.descriptor, metadata: metadata, isRoot: rootIsFinal && index == chain.count - 1)
                node.securityStamp = stamp
            } else {
                try Self.validateDirectoryMode(metadata, isRoot: rootIsFinal && index == chain.count - 1)
            }
        }
    }

    private func validateRoot(_ descriptor: Int32) throws {
        guard let root = pinnedDirectories.last else { throw StorageError.unsafeRoot }
        try validateChain(pinnedDirectories, rootIsFinal: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw posixError() }
        guard RootIdentity(metadata) == root.identity else { throw StorageError.changed }
    }

    private static func validateDirectoryMode(_ metadata: stat, isRoot: Bool) throws {
        guard metadata.st_mode & S_IFMT == S_IFDIR else { throw StorageError.unsafeRoot }
        if isRoot {
            guard metadata.st_uid == geteuid(), metadata.st_mode & 0o7777 == 0o700 else { throw StorageError.unsafeRoot }
        } else {
            guard metadata.st_uid == geteuid() || metadata.st_uid == 0 else { throw StorageError.unsafeRoot }
            // Sticky directories protect entries owned by the current user even
            // when the OS permits other users to create their own temporary files.
            guard metadata.st_mode & 0o022 == 0 || metadata.st_mode & S_ISVTX != 0 else { throw StorageError.unsafeRoot }
        }
    }

    private static func validateDirectory(_ descriptor: Int32, metadata: stat, isRoot: Bool) throws {
        try validateDirectoryMode(metadata, isRoot: isRoot)
        try validateACL(descriptor, privateAccess: isRoot)
    }

    /// Internal migration helper. Production calls it only for the app's actual
    /// default per-user folder after all pinned parents have passed validation.
    static func tightenLegacyDefaultPermissions(descriptor: Int32) throws -> Bool {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw StorageError.unsafeRoot }
        guard metadata.st_mode & S_IFMT == S_IFDIR, metadata.st_uid == geteuid() else { throw StorageError.unsafeRoot }
        if metadata.st_mode & 0o7777 == 0o700 {
            try validateACL(descriptor, privateAccess: true)
            return false
        }
        guard metadata.st_mode & 0o7777 == 0o755 else { throw StorageError.unsafeRoot }
        try validateACL(descriptor, privateAccess: true)
        guard fchmod(descriptor, 0o700) == 0 else { throw StorageError.unsafeRoot }
        guard fstat(descriptor, &metadata) == 0 else { throw StorageError.unsafeRoot }
        try validateDirectory(descriptor, metadata: metadata, isRoot: true)
        return true
    }

    private static func validateACL(_ descriptor: Int32, privateAccess: Bool) throws {
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return }
            throw StorageError.unsafeRoot
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw StorageError.unsafeRoot }
        var currentUser = [UInt8](repeating: 0, count: 16)
        let userResult = currentUser.withUnsafeMutableBufferPointer { membershipUserUUID(geteuid(), $0.baseAddress!) }
        guard userResult == 0 else { throw StorageError.unsafeRoot }
        let writePermissions = UInt64(ACL_WRITE_DATA.rawValue | ACL_DELETE.rawValue | ACL_APPEND_DATA.rawValue |
                                      ACL_DELETE_CHILD.rawValue | ACL_WRITE_ATTRIBUTES.rawValue | ACL_WRITE_EXTATTRIBUTES.rawValue |
                                      ACL_WRITE_SECURITY.rawValue | ACL_CHANGE_OWNER.rawValue)
        var entry: acl_entry_t?
        var position = Int32(ACL_FIRST_ENTRY.rawValue)
        var count = 0
        while true {
            errno = 0
            let result = acl_get_entry(acl, position, &entry)
            if result != 0 {
                guard errno == ENOENT || errno == EINVAL else { throw StorageError.unsafeRoot }
                break
            }
            guard let entry else { throw StorageError.unsafeRoot }
            count += 1
            guard count <= 128 else { throw StorageError.unsafeRoot }
            position = Int32(ACL_NEXT_ENTRY.rawValue)
            var tag = ACL_UNDEFINED_TAG
            var mask: acl_permset_mask_t = 0
            guard acl_get_tag_type(entry, &tag) == 0, acl_get_permset_mask_np(entry, &mask) == 0 else { throw StorageError.unsafeRoot }
            guard tag == ACL_EXTENDED_ALLOW, privateAccess ? mask != 0 : mask & writePermissions != 0 else { continue }
            guard let qualifier = acl_get_qualifier(entry) else { throw StorageError.unsafeRoot }
            defer { acl_free(qualifier) }
            let principal = qualifier.assumingMemoryBound(to: UInt8.self)
            guard currentUser.elementsEqual(UnsafeBufferPointer(start: principal, count: 16)) else { throw StorageError.unsafeRoot }
        }
    }

    private static func validateFileAccess(_ descriptor: Int32, metadata: stat) throws {
        guard metadata.st_uid == geteuid(), metadata.st_mode & 0o022 == 0 else { throw StorageError.unsafeRoot }
        try validateACL(descriptor, privateAccess: true)
    }

    private func reservedName(for url: URL) throws -> String {
        let parent = "/" + url.deletingLastPathComponent().path.split(separator: "/").filter { $0 != "." }.joined(separator: "/")
        guard parent == rootPath else { throw StorageError.fileType }
        return url.lastPathComponent
    }

    /// The descriptor check prevents a path-swap from following a symlink after lstat.
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let owner: uid_t
        let group: gid_t
        let links: nlink_t
        let bytes: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ value: stat) {
            device = value.st_dev
            inode = value.st_ino
            mode = value.st_mode
            owner = value.st_uid
            group = value.st_gid
            links = value.st_nlink
            bytes = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private struct BoardFile {
        let data: Data
        let identity: FileIdentity
    }

    private func fileIdentity(at url: URL, directoryFD: Int32) throws -> FileIdentity {
        try validateRoot(directoryFD)
        var metadata = stat()
        guard fstatat(directoryFD, try reservedName(for: url), &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        return FileIdentity(metadata)
    }

    private func readBoardFile(at url: URL, directoryFD: Int32) throws -> BoardFile {
        try validateRoot(directoryFD)
        let filename = try reservedName(for: url)
        var pathMetadata = stat()
        guard fstatat(directoryFD, filename, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        guard pathMetadata.st_mode & S_IFMT == S_IFREG, pathMetadata.st_nlink == 1 else { throw StorageError.fileType }
        guard pathMetadata.st_uid == geteuid(), pathMetadata.st_mode & 0o022 == 0 else { throw StorageError.unsafeRoot }
        let descriptor = openat(directoryFD, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw StorageError.fileType }
            throw posixError()
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw posixError() }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1 else { throw StorageError.fileType }
        try Self.validateFileAccess(descriptor, metadata: metadata)
        guard metadata.st_size >= 0, metadata.st_size <= BoardStorageLimits.fileBytes else { throw StorageError.fileSize }
        let identity = FileIdentity(metadata)
        guard identity == FileIdentity(pathMetadata) else { throw StorageError.changed }
        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let capacity = min(buffer.count, BoardStorageLimits.fileBytes - data.count + 1)
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, capacity) }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if count == 0 {
                var finalMetadata = stat()
                guard fstat(descriptor, &finalMetadata) == 0 else { throw posixError() }
                guard FileIdentity(finalMetadata) == identity,
                      try fileIdentity(at: url, directoryFD: directoryFD) == identity, data.count == identity.bytes else { throw StorageError.changed }
                try Self.validateFileAccess(descriptor, metadata: finalMetadata)
                return BoardFile(data: data, identity: identity)
            }
            guard count <= BoardStorageLimits.fileBytes - data.count else { throw StorageError.fileSize }
            buffer.withUnsafeBufferPointer { data.append($0.baseAddress!, count: count) }
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// Write a new regular file first, then check the destination immediately before rename.
    private func atomicWrite(_ data: Data, to url: URL, expected: FileIdentity?, directoryFD: Int32) throws {
        _ = try reservedName(for: url)
        try validateRoot(directoryFD)
        let temporaryName = url.lastPathComponent + ".write-" + UUID().uuidString + ".tmp"
        let descriptor = openat(directoryFD, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        var renamed = false
        defer {
            close(descriptor)
            if !renamed { unlinkat(directoryFD, temporaryName, 0) }
        }
        var createdMetadata = stat()
        guard fstat(descriptor, &createdMetadata) == 0 else { throw posixError() }
        try Self.validateFileAccess(descriptor, metadata: createdMetadata)
        try validateRoot(directoryFD)
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < bytes.count {
                let count = write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) }
                offset += count
            }
        }
        var temporaryMetadata = stat()
        guard fstat(descriptor, &temporaryMetadata) == 0 else { throw posixError() }
        try Self.validateFileAccess(descriptor, metadata: temporaryMetadata)
        var pathMetadata = stat()
        guard fstatat(directoryFD, temporaryName, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw StorageError.changed }
        guard FileIdentity(pathMetadata) == FileIdentity(temporaryMetadata) else { throw StorageError.changed }
        try validateRoot(directoryFD)
        let result = fstatat(directoryFD, url.lastPathComponent, &pathMetadata, AT_SYMLINK_NOFOLLOW)
        if let expected {
            guard result == 0, FileIdentity(pathMetadata) == expected else { throw StorageError.changed }
        } else {
            guard result < 0, errno == ENOENT else { throw StorageError.changed }
        }
        let flags = expected == nil ? UInt32(RENAME_EXCL) : 0
        guard renameatx_np(directoryFD, temporaryName, directoryFD, url.lastPathComponent, flags) == 0 else {
            if errno == EEXIST { throw StorageError.changed }
            throw posixError()
        }
        renamed = true
    }

    /// Scan bounded bytes before JSONDecoder allocates its representation of nested values.
    private func validateJSONStructure(_ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            var index = 0
            var depth = 0
            var tokens = 0
            while index < bytes.count {
                switch bytes[index] {
                case 9, 10, 13, 32, 44, 58: index += 1
                case 123, 91:
                    depth += 1
                    tokens += 1
                    guard depth <= BoardStorageLimits.jsonDepth else { throw StorageError.structure }
                    index += 1
                case 125, 93:
                    depth -= 1
                    tokens += 1
                    guard depth >= 0 else { throw StorageError.structure }
                    index += 1
                case 34:
                    tokens += 1
                    index += 1
                    var closed = false
                    while index < bytes.count {
                        if bytes[index] == 34 { index += 1; closed = true; break }
                        index += bytes[index] == 92 ? 2 : 1
                    }
                    guard closed else { throw StorageError.structure }
                default:
                    tokens += 1
                    while index < bytes.count && ![9, 10, 13, 32, 44, 58, 123, 125, 91, 93, 34].contains(bytes[index]) { index += 1 }
                }
                guard tokens <= BoardStorageLimits.jsonTokens else { throw StorageError.structure }
            }
            guard depth == 0 else { throw StorageError.structure }
        }
    }

    private func preserveUnreadableFile(at url: URL, expected: FileIdentity?, directoryFD: Int32) throws {
        let filename = try reservedName(for: url)
        let current = try fileIdentity(at: url, directoryFD: directoryFD)
        guard let expected, current == expected else { throw StorageError.changed }
        let kind = current.mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFLNK else { throw StorageError.fileType }
        if kind == S_IFREG {
            let descriptor = openat(directoryFD, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw StorageError.changed }
            defer { close(descriptor) }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, FileIdentity(metadata) == current else { throw StorageError.changed }
            try Self.validateFileAccess(descriptor, metadata: metadata)
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let preserved = "\(url.deletingPathExtension().lastPathComponent).corrupt-\(stamp)-\(UUID().uuidString).json"
        try validateRoot(directoryFD)
        guard renameatx_np(directoryFD, filename, directoryFD, preserved, UInt32(RENAME_EXCL)) == 0 else { throw posixError() }
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
        return L(storageErrorKey(storageError))
    }

    private func storageErrorKey(_ storageError: StorageError) -> String {
        switch storageError {
        case .unsupportedVersion: return "error.unsupportedVersion"
        case .duplicateIdentifiers: return "error.duplicateIdentifiers"
        case .invalidWIPLimit: return "error.invalidWIPLimit"
        case .fileType: return "error.storageFileType"
        case .fileSize: return "error.storageFileSize"
        case .cardCount: return "error.storageCardCount"
        case .fieldSize: return "error.storageFieldSize"
        case .textBudget: return "error.storageTextBudget"
        case .structure: return "error.storageStructure"
        case .changed: return "error.storageChanged"
        case .unsafeRoot: return "error.storageUnsafeRoot"
        }
    }

}
