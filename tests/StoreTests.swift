import Foundation
import Darwin

@main
struct StoreTests {
    @MainActor
    static func main() throws {
        try persistenceAndFields()
        try ordering()
        try undoAndRedo()
        try boundedAndGroupedHistory()
        try unlimitedCards()
        try wipEnforcement()
        try configurableWIP()
        try exclusiveColumnColors()
        try writeFailure()
        try corruptionRecovery()
        try corruptBothFiles()
        try oversizedSparseFiles()
        try symbolicAndHardLinks()
        try nonregularEntries()
        try resourceBudgetFixtures()
        try resourceBudgetMutations()
        try serializedBudget()
        try externallyChangedBoard()
        try rootDirectoryProtection()
        try privateLeafLinkIsolation()
        try parentPathTrust()
        try privatePermissions()
        try accessControlLists()
        try legacyDefaultPermissions()
        try parentSwapProtection()
        try interruptedInitialLoad()
        print("PASS: 26 grupos de testes do modelo, da persistência e da proteção do armazenamento")
    }

    @MainActor
    static func persistenceAndFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let id = try unwrap(store.createCard(in: .backlog, color: .yellow))
        let created = try unwrap(store.card(id: id))
        try expect(store.updateCard(id: id, title: "Aula de quarta", notes: "Descrição longa\nCom acentos, ç e emoji 📝", column: .review, color: .rose), "Aceita atualização")
        store.setBoardTitle("Produção editorial")
        let expected = store.snapshot
        try expect(store.lastSaved != nil && store.saveError == nil, "Indica salvamento")
        try expect(FileManager.default.fileExists(atPath: store.backupURL.path), "Cria cópia anterior")
        let reopened = BoardStore(directory: directory)
        try expect(reopened.snapshot == expected, "Reabre todos os campos e ordem")
        let persisted = try unwrap(reopened.card(id: id))
        try expect(persisted.color == .purple, "Cor acompanha coluna Revisão")
        try expect(persisted.createdAt == created.createdAt, "Preserva criação")
        try expect(persisted.updatedAt >= created.updatedAt, "Atualiza edição")
        try expect(reopened.cards(in: .review, query: "descricao").map(\.id) == [id], "Busca ignora acentos")
        try expect(reopened.cards(in: .review, query: "  ").count == 1, "Busca vazia preserva cartões")
    }

    @MainActor
    static func ordering() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let a = try unwrap(store.createCard(in: .backlog))
        let b = try unwrap(store.createCard(in: .backlog))
        let c = try unwrap(store.createCard(in: .backlog))
        let x = try unwrap(store.createCard(in: .review))
        let y = try unwrap(store.createCard(in: .review))
        try expect(store.moveCard(id: c, to: .backlog, before: a), "Move acima na coluna")
        try expect(store.cards(in: .backlog).map(\.id) == [c, a, b], "Ordem acima")
        try expect(store.moveCard(id: c, to: .backlog), "Move ao fim")
        try expect(store.cards(in: .backlog).map(\.id) == [a, b, c], "Ordem ao fim")
        try expect(store.moveCard(id: a, to: .review, before: y), "Move entre colunas")
        try expect(store.cards(in: .review).map(\.id) == [x, a, y], "Posição entre colunas")
        try expect(store.moveCard(id: x, to: .review, before: y), "Move abaixo na coluna")
        try expect(store.cards(in: .review).map(\.id) == [a, x, y], "Ordem abaixo")
        let unchanged = store.snapshot
        try expect(store.moveCard(id: y, to: .review, before: y), "Destino próprio aceita sem alterar")
        try expect(!store.moveCard(id: y, to: .review, before: b), "Rejeita destino em outra coluna")
        try expect(store.snapshot == unchanged, "Destinos inválidos preservam quadro")
        try expect(BoardStore(directory: directory).snapshot == store.snapshot, "Persiste reordenação")
    }

    @MainActor
    static func undoAndRedo() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let id = try unwrap(store.createCard(in: .backlog))
        let before = store.snapshot
        store.updateCard(id: id, title: "Depois")
        let after = store.snapshot
        try expect(store.canUndo && !store.canRedo, "Disponibilidade inicial")
        try expect(store.undo() && store.snapshot == before, "Desfaz conteúdo")
        try expect(BoardStore(directory: directory).snapshot == before, "Desfazer persiste imediatamente")
        try expect(store.canRedo && store.redo() && store.snapshot == after, "Refaz conteúdo")
        try expect(BoardStore(directory: directory).snapshot == after, "Refazer persiste imediatamente")
        store.undo()
        store.setBoardTitle("Novo nome")
        try expect(!store.canRedo && !store.redo(), "Nova ação limpa refazer")
        store.deleteCard(id: id)
        try expect(store.card(id: id) == nil && store.undo() && store.card(id: id) != nil, "Desfaz exclusão")
    }

    @MainActor
    static func unlimitedCards() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cards = (0..<1_200).map { KanbanCard(title: "Cartão \($0)", notes: "Conteúdo \($0)", column: .backlog) }
        let fixture = BoardSnapshot(cards: cards, boardTitle: "Mil e duzentos cartões")
        try JSONEncoder().encode(fixture).write(to: directory.appendingPathComponent("board.json"), options: .atomic)
        let store = BoardStore(directory: directory)
        try expect(store.cards(in: .backlog).count == 1_200, "Carrega mais de mil cartões")
        let added = try unwrap(store.createCard(in: .backlog))
        try expect(store.cards(in: .backlog).count == 1_201, "Acrescenta sem limite")
        let started = ProcessInfo.processInfo.systemUptime
        store.updateCard(id: added, title: "Mais um")
        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        print(String(format: "BENCH: atualização e salvamento atômico de 1.201 cartões em %.2f ms", milliseconds))
        try expect(BoardStore(directory: directory).cards(in: .backlog).count == 1_201, "Persiste todos os cartões")
    }

    @MainActor
    static func boundedAndGroupedHistory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let id = try unwrap(store.createCard(in: .backlog))
        let beforeBurst = store.snapshot
        let started = ProcessInfo.processInfo.systemUptime
        for index in 0..<10_000 {
            store.updateCard(id: id, title: "Edição \(index)", notes: "Nota \(index)")
        }
        let burstEnd = store.snapshot
        let seconds = ProcessInfo.processInfo.systemUptime - started
        print(String(format: "BENCH: 10.000 edições com salvamento imediato em %.2f s", seconds))
        try expect(store.undo() && store.snapshot == beforeBurst, "Uma ação desfaz a sequência de dez mil edições")
        try expect(store.redo() && store.snapshot == burstEnd, "Uma ação refaz toda a sequência")
        try expect(BoardStore(directory: directory).snapshot == burstEnd, "Sequência persistida")

        store.updateCard(id: id, title: "Primeira sequência")
        store.moveCard(id: id, to: .review)
        let afterMove = store.snapshot
        store.updateCard(id: id, notes: "Segunda sequência")
        try expect(store.undo() && store.snapshot == afterMove, "Mover coluna separa as sequências de texto")
        store.redo()
        for index in 0..<250 {
            store.setBoardTitle("Quadro \(index)")
        }
        let final = store.snapshot
        var undoCount = 0
        while store.undo() { undoCount += 1 }
        try expect(undoCount == 100, "Histórico limita desfazer a cem snapshots")
        var redoCount = 0
        while store.redo() { redoCount += 1 }
        try expect(redoCount == 100 && store.snapshot == final, "Refazer respeita limite e restaura quadro final")
    }

    @MainActor
    static func wipEnforcement() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let first = try unwrap(store.createCard(in: .doing))
        let second = try unwrap(store.createCard(in: .doing))
        let waiting = try unwrap(store.createCard(in: .backlog))
        let before = store.snapshot
        try expect(store.createCard(in: .doing) == nil && store.wipAlert, "Bloqueia terceira criação em Fazendo")
        store.wipAlert = false
        try expect(!store.moveCard(id: waiting, to: .doing) && store.wipAlert, "Bloqueia movimento em Fazendo")
        store.wipAlert = false
        try expect(!store.updateCard(id: waiting, title: "Edição bloqueada", notes: "Bloqueada", column: .doing, color: .rose) && store.wipAlert, "Bloqueia edição integral")
        try expect(store.snapshot == before, "Bloqueio preserva todos os campos e histórico")
        try expect(store.cards(in: .doing, query: "inexistente").isEmpty, "Busca pode ocultar todos")
        try expect(store.createCard(in: .doing) == nil, "WIP conta cartões ocultos pela busca")
        try expect(store.updateCard(id: first, title: "Trabalho em curso", column: .doing), "Permite editar cartão existente em Fazendo")
        try expect(store.moveCard(id: second, to: .doing, before: first), "Permite reordenar Fazendo cheio")
        try expect(store.moveCard(id: first, to: .review), "Libera vaga ao revisar")
        try expect(store.moveCard(id: waiting, to: .doing), "Ocupa vaga liberada")
        try expect(store.cards(in: .doing).count == 2, "Limite preservado")
        let reopened = BoardStore(directory: directory)
        try expect(reopened.cards(in: .doing).count == 2 && reopened.createCard(in: .doing) == nil, "WIP preservado ao reabrir")
    }

    @MainActor
    static func configurableWIP() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        _ = try unwrap(store.createCard(in: .doing))
        _ = try unwrap(store.createCard(in: .doing))
        try expect(store.wipLimit == 2 && store.createCard(in: .doing) == nil, "Limite padrão dois")
        try expect(store.setWIPLimit(3), "Permite aumentar limite")
        _ = try unwrap(store.createCard(in: .doing))
        try expect(store.cards(in: .doing).count == 3, "Permite terceiro após aumentar")
        try expect(!store.setWIPLimit(2) && store.wipLimit == 3, "Rejeita redução abaixo da ocupação")
        try expect(!store.setWIPLimit(0) && !store.setWIPLimit(-1), "Rejeita limites inválidos")
        try expect(BoardStore(directory: directory).wipLimit == 3, "Persiste limite configurado")
        try expect(store.setWIPLimit(10_000), "Sem teto artificial de configuração")

        let legacyDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: legacyDirectory) }
        let legacy = Data("{\"schemaVersion\":1,\"cards\":[],\"boardTitle\":\"Quadro antigo\"}".utf8)
        try legacy.write(to: legacyDirectory.appendingPathComponent("board.json"))
        try expect(BoardStore(directory: legacyDirectory).wipLimit == 2, "Arquivos sem WIP recebem padrão dois")
    }

    @MainActor
    static func exclusiveColumnColors() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        try expect(Set(KanbanColumn.allCases.map(\.noteColor)).count == 4, "Cada coluna tem uma cor exclusiva")
        var identifiers: [KanbanColumn: UUID] = [:]
        for column in KanbanColumn.allCases {
            let id = try unwrap(store.createCard(in: column, color: .rose))
            identifiers[column] = id
            try expect(store.card(id: id)?.color == column.noteColor, "Criação usa cor fixa da coluna")
            store.updateCard(id: id, title: column.title, color: .rose)
            try expect(store.card(id: id)?.color == column.noteColor, "Edição respeita cor fixa da coluna")
        }
        let first = try unwrap(identifiers[.backlog])
        try expect(store.updateCard(id: first, column: .doing, color: .rose), "Editar coluna aceita vaga")
        try expect(store.card(id: first)?.color == .blue, "Edição de coluna atualiza a cor")
        try expect(store.moveCard(id: first, to: .review), "Move para Revisão")
        try expect(store.card(id: first)?.color == .purple, "Movimento atualiza a cor")
        try expect(store.moveCard(id: first, to: .done), "Move para Feito")
        try expect(store.card(id: first)?.color == .green, "Feito usa verde")
        let reopened = BoardStore(directory: directory)
        try expect(reopened.snapshot.cards.allSatisfy { $0.color == $0.column.noteColor }, "Cores exclusivas persistem ao reabrir")

        let legacyDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: legacyDirectory) }
        let legacyCards = KanbanColumn.allCases.map { KanbanCard(title: $0.title, column: $0, color: .rose) }
        let legacy = try JSONEncoder().encode(BoardSnapshot(cards: legacyCards))
        let primary = legacyDirectory.appendingPathComponent("board.json")
        let backup = legacyDirectory.appendingPathComponent("board.backup.json")
        try legacy.write(to: primary)
        try legacy.write(to: backup)
        let migrated = BoardStore(directory: legacyDirectory)
        try expect(migrated.snapshot.cards.allSatisfy { $0.color == $0.column.noteColor }, "Leitura normaliza cores antigas")
        try Data("Arquivo corrompido".utf8).write(to: primary)
        let recovered = BoardStore(directory: legacyDirectory)
        try expect(recovered.recoveryMessage != nil && recovered.snapshot.cards.allSatisfy { $0.color == $0.column.noteColor }, "Recuperação de backup também normaliza cores")
    }

    @MainActor
    static func writeFailure() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("arquivo-no-lugar-da-pasta")
        try Data("ocupado".utf8).write(to: blocked)
        let store = BoardStore(directory: blocked)
        let id = try unwrap(store.createCard(in: .backlog))
        try expect(store.card(id: id) != nil, "Falha de disco preserva cartão em memória")
        try expect(store.saveError != nil && store.lastSaved == nil && !store.flush(), "Expõe falha de salvamento")
        try expect(try Data(contentsOf: blocked) == Data("ocupado".utf8), "Preserva arquivo bloqueador")
        try FileManager.default.removeItem(at: blocked)
        try expect(store.flush() && store.saveError == nil, "Nova tentativa salva quando pasta fica disponível")
        try expect(BoardStore(directory: blocked).card(id: id) != nil, "Recupera edição após falha de escrita")
    }

    @MainActor
    static func corruptionRecovery() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let id = try unwrap(store.createCard(in: .backlog))
        store.updateCard(id: id, title: "Última cópia boa")
        let backupExpected = store.snapshot
        store.updateCard(id: id, title: "Última sessão")
        let damaged = Data("{ cartão corrompido".utf8)
        try damaged.write(to: store.documentURL, options: .atomic)
        let recovered = BoardStore(directory: directory)
        try expect(recovered.snapshot == backupExpected && recovered.recoveryMessage != nil, "Recupera cópia e avisa")
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".corrupt-") }
        try expect(preserved.count == 1, "Preserva arquivo corrompido")
        try expect(try Data(contentsOf: preserved[0]) == damaged, "Cópia preserva bytes originais")
        try expect(recovered.flush() && BoardStore(directory: directory).snapshot == backupExpected, "Regrava recuperação válida")
        try expect(FileManager.default.fileExists(atPath: preserved[0].path), "Salvamento preserva evidência")
    }

    @MainActor
    static func corruptBothFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = directory.appendingPathComponent("board.json")
        let backup = directory.appendingPathComponent("board.backup.json")
        try Data("primary damaged".utf8).write(to: primary)
        try Data("backup damaged".utf8).write(to: backup)
        let store = BoardStore(directory: directory)
        try expect(store.snapshot.cards.isEmpty && store.recoveryMessage != nil, "Informa dois arquivos ilegíveis")
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".corrupt-") }
        try expect(preserved.count == 2, "Preserva os dois arquivos")
        let contents = try preserved.map { try String(contentsOf: $0, encoding: .utf8) }
        try expect(Set(contents) == Set(["primary damaged", "backup damaged"]), "Preserva os dois conteúdos")
        try expect(store.flush(), "Permite um novo quadro com cópias preservadas")
    }

    @MainActor
    static func oversizedSparseFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = directory.appendingPathComponent("board.json")
        try Data().write(to: primary)
        let handle = try FileHandle(forWritingTo: primary)
        try handle.truncate(atOffset: UInt64(BoardStorageLimits.fileBytes + 1))
        try handle.close()
        let validBackup = BoardSnapshot(cards: [KanbanCard(title: "Cópia segura")])
        try JSONEncoder().encode(validBackup).write(to: directory.appendingPathComponent("board.backup.json"))
        let started = ProcessInfo.processInfo.systemUptime
        let store = BoardStore(directory: directory)
        try expect(store.snapshot == validBackup && store.recoveryMessage != nil, "Recupera backup sem alocar arquivo sparse excessivo")
        try expect(ProcessInfo.processInfo.systemUptime - started < 2, "Recusa sparse pelo tamanho antes da leitura")
        let preserved = try quarantinedFiles(in: directory)
        try expect(preserved.count == 1, "Preserva sparse rejeitado")
        let length = try FileManager.default.attributesOfItem(atPath: preserved[0].path)[.size] as? NSNumber
        try expect(length?.intValue == BoardStorageLimits.fileBytes + 1, "Quarentena mantém comprimento original")
        try expect(store.flush() && BoardStore(directory: directory).snapshot == validBackup, "Grava quadro recuperado sem sobrescrever sparse")

        let backup = directory.appendingPathComponent("board.backup.json")
        try Data().write(to: backup, options: .atomic)
        let backupHandle = try FileHandle(forWritingTo: backup)
        try backupHandle.truncate(atOffset: UInt64(BoardStorageLimits.fileBytes + 10))
        try backupHandle.close()
        let reopened = BoardStore(directory: directory)
        try expect(reopened.snapshot == validBackup && reopened.recoveryMessage != nil, "Valida backup mesmo com primary válido")
        try expect(try quarantinedFiles(in: directory).count == 2, "Preserva backup sparse")
    }

    @MainActor
    static func symbolicAndHardLinks() throws {
        let external = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: external) }
        let target = external.appendingPathComponent("external.json")
        let bytes = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "Arquivo externo")]))
        try bytes.write(to: target)
        for dangling in [false, true] {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let destination = dangling ? external.appendingPathComponent("ausente.json") : target
            let primary = directory.appendingPathComponent("board.json")
            try FileManager.default.createSymbolicLink(at: primary, withDestinationURL: destination)
            let store = BoardStore(directory: directory)
            try expect(store.snapshot.cards.isEmpty && store.recoveryMessage != nil, "Recusa link sem seguir seu alvo")
            let preserved = try quarantinedFiles(in: directory)
            try expect(preserved.count == 1, "Preserva a entrada do link, inclusive dangling")
            try expect(try FileManager.default.destinationOfSymbolicLink(atPath: preserved[0].path) == destination.path, "Mantém alvo do link preservado")
            try expect(store.flush(), "Novo arquivo regular após preservar link")
            try expect(try Data(contentsOf: target) == bytes, "Alvo externo permanece intacto")
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.linkItem(at: target, to: directory.appendingPathComponent("board.json"))
        let store = BoardStore(directory: directory)
        try expect(store.snapshot.cards.isEmpty && store.recoveryMessage != nil, "Recusa arquivo com hardlink")
        try expect(store.flush() && Data(contentsOf: target) == bytes, "Não modifica bytes de alias externo")
    }

    @MainActor
    static func nonregularEntries() throws {
        for (filename, fifo) in ["board.json", "board.backup.json"].flatMap({ filename in [false, true].map { (filename, $0) } }) {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let primary = directory.appendingPathComponent(filename)
            if filename == "board.backup.json" {
                try JSONEncoder().encode(BoardSnapshot()).write(to: directory.appendingPathComponent("board.json"))
            }
            if fifo {
                try expect(mkfifo(primary.path, 0o600) == 0, "Cria FIFO sintético")
            } else {
                try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: false)
                try Data("Não tocar".utf8).write(to: primary.appendingPathComponent("marker.txt"))
            }
            let started = ProcessInfo.processInfo.systemUptime
            let store = BoardStore(directory: directory)
            try expect(ProcessInfo.processInfo.systemUptime - started < 2, "Não bloqueia ao encontrar entrada especial")
            try expect(store.saveError != nil && !store.flush(), "Bloqueia salvamento sobre entrada não regular")
            try expect(try quarantinedFiles(in: directory).isEmpty, "Não renomeia diretório ou FIFO")
            var metadata = stat()
            try expect(lstat(primary.path, &metadata) == 0, "Preserva entrada não regular")
            try expect(metadata.st_mode & S_IFMT == (fifo ? S_IFIFO : S_IFDIR), "Preserva tipo de entrada")
            if !fifo {
                try expect(try String(contentsOf: primary.appendingPathComponent("marker.txt"), encoding: .utf8) == "Não tocar", "Preserva conteúdo do diretório")
            }
        }
    }

    @MainActor
    static func resourceBudgetFixtures() throws {
        let backup = BoardSnapshot(cards: [KanbanCard(title: "Volta para a cópia")])
        var excessive = BoardSnapshot(cards: (0...BoardStorageLimits.cards).map { _ in KanbanCard() })
        try rejectedFixture(JSONEncoder().encode(excessive), backup: backup, reason: "Contagem excessiva")
        excessive = BoardSnapshot(boardTitle: String(repeating: "📝", count: BoardStorageLimits.boardTitleBytes / 4 + 1))
        try rejectedFixture(JSONEncoder().encode(excessive), backup: backup, reason: "Quadro excede bytes UTF-8")
        excessive = BoardSnapshot(cards: [KanbanCard(title: String(repeating: "x", count: BoardStorageLimits.cardTitleBytes + 1))])
        try rejectedFixture(JSONEncoder().encode(excessive), backup: backup, reason: "Título excessivo")
        excessive = BoardSnapshot(cards: [KanbanCard(notes: String(repeating: "x", count: BoardStorageLimits.cardNotesBytes + 1))])
        try rejectedFixture(JSONEncoder().encode(excessive), backup: backup, reason: "Notas excessivas")
        let note = String(repeating: "x", count: BoardStorageLimits.cardNotesBytes)
        excessive = BoardSnapshot(cards: (0..<33).map { _ in KanbanCard(notes: note) }, boardTitle: "")
        try rejectedFixture(JSONEncoder().encode(excessive), backup: backup, reason: "Texto agregado excessivo")
        let card = KanbanCard()
        try rejectedFixture(JSONEncoder().encode(BoardSnapshot(cards: [card, card])), backup: backup, reason: "IDs repetidos")
        let prefix = "{\"schemaVersion\":1,\"cards\":[],\"boardTitle\":\"\",\"unused\":"
        let nested = prefix + String(repeating: "[", count: BoardStorageLimits.jsonDepth) + "0" + String(repeating: "]", count: BoardStorageLimits.jsonDepth) + "}"
        try rejectedFixture(Data(nested.utf8), backup: backup, reason: "Profundidade excessiva")
        let tokenBomb = prefix + "[" + String(repeating: "0,", count: BoardStorageLimits.jsonTokens) + "0]}"
        try rejectedFixture(Data(tokenBomb.utf8), backup: backup, reason: "Tokens excessivos")

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = BoardSnapshot(cards: [KanbanCard(notes: "Texto literal [{\\\" }] e emoji 📝")], boardTitle: String(repeating: "📝", count: 256))
        try JSONEncoder().encode(valid).write(to: directory.appendingPathComponent("board.json"))
        try expect(BoardStore(directory: directory).snapshot == valid, "Aceita fronteira UTF-8 e delimitadores dentro de texto")
    }

    @MainActor
    static func resourceBudgetMutations() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let id = try unwrap(store.createCard())
        let before = store.snapshot
        let disk = try Data(contentsOf: store.documentURL)
        let undoBefore = store.canUndo
        let oversizedTitle = String(repeating: "x", count: BoardStorageLimits.cardTitleBytes + 1)
        try expect(!store.updateCard(id: id, title: oversizedTitle), "Recusa título antes de mutar")
        try expect(store.storageAlert == "error.storageFieldSize" && store.saveError == nil, "Alerta de limite separado do autosave")
        store.storageAlert = nil
        try expect(!store.updateCard(id: id, title: oversizedTitle) && store.storageAlert == nil, "Não repete popup a cada tecla recusada")
        try expect(store.snapshot == before && store.canUndo == undoBefore, "Rejeição preserva snapshot e histórico")
        try expect(try Data(contentsOf: store.documentURL) == disk, "Rejeição não escreve em disco")
        try expect(store.updateCard(id: id, title: ""), "Aceita retorno ao texto original")
        try expect(!store.updateCard(id: id, title: oversizedTitle) && store.storageAlert != nil, "Nova recusa alerta após mudança aceita")
        try expect(!store.setBoardTitle(String(repeating: "📝", count: 257)), "Configurações respeitam UTF-8")
        try expect(!store.updateCard(id: id, notes: String(repeating: "x", count: BoardStorageLimits.cardNotesBytes + 1)), "Editor respeita limite de notas")

        let fullDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fullDirectory) }
        let full = BoardSnapshot(cards: (0..<BoardStorageLimits.cards).map { _ in KanbanCard() }, boardTitle: "")
        try JSONEncoder().encode(full).write(to: fullDirectory.appendingPathComponent("board.json"))
        let fullStore = BoardStore(directory: fullDirectory)
        try expect(fullStore.snapshot.cards.count == BoardStorageLimits.cards, "Aceita dez mil cartões válidos")
        try expect(fullStore.createCard() == nil && fullStore.storageAlert == "error.storageCardCount", "Bloqueia criação acima do orçamento")
        try expect(fullStore.snapshot == full && !fullStore.canUndo, "Card-count recusado não cria histórico")

        let aggregateDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: aggregateDirectory) }
        let notes = String(repeating: "x", count: BoardStorageLimits.cardNotesBytes)
        let aggregate = BoardSnapshot(cards: (0..<32).map { _ in KanbanCard(notes: notes) }, boardTitle: "")
        try JSONEncoder().encode(aggregate).write(to: aggregateDirectory.appendingPathComponent("board.json"))
        let aggregateStore = BoardStore(directory: aggregateDirectory)
        try expect(aggregateStore.snapshot == aggregate, "Aceita fronteira de oito MiB de texto")
        try expect(!aggregateStore.updateCard(id: aggregate.cards[0].id, title: "x") && aggregateStore.storageAlert == "error.storageTextBudget", "Mutação respeita orçamento textual total")
        try expect(aggregateStore.snapshot == aggregate, "Não trunca texto ao atingir orçamento")

        let blockedDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: blockedDirectory) }
        let blocked = blockedDirectory.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: blocked)
        let blockedStore = BoardStore(directory: blocked)
        let blockedID = try unwrap(blockedStore.createCard())
        let saveFailure = blockedStore.saveError
        try expect(saveFailure != nil && !blockedStore.updateCard(id: blockedID, title: oversizedTitle), "Recusa recurso durante falha real de autosave")
        try expect(blockedStore.saveError == saveFailure, "Não substitui diagnóstico de disco por alerta de recurso")
    }

    @MainActor
    static func serializedBudget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = String(repeating: "\u{0001}", count: BoardStorageLimits.cardNotesBytes)
        var cards = (0..<10).map { _ in KanbanCard(notes: notes) }
        let empty = KanbanCard()
        cards.append(empty)
        let snapshot = BoardSnapshot(cards: cards, boardTitle: "")
        let bytes = try JSONEncoder().encode(snapshot)
        try expect(bytes.count < BoardStorageLimits.fileBytes, "Fixture escapado cabe no limite de arquivo")
        try bytes.write(to: directory.appendingPathComponent("board.json"))
        let store = BoardStore(directory: directory)
        try expect(store.snapshot == snapshot, "Carrega texto escapado válido")
        try expect(!store.updateCard(id: empty.id, notes: notes) && store.storageAlert == "error.storageFileSize", "Recusa mutação cujo JSON escapado excederia o limite")
        try expect(store.snapshot == snapshot && Data(contentsOf: store.documentURL) == bytes, "Preserva quadro reabrível após rejeição serializada")
        try expect(BoardStore(directory: directory).snapshot == snapshot, "Toda mutação aceita permanece reabrível")
    }

    @MainActor
    static func externallyChangedBoard() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let id = try unwrap(store.createCard())
        store.updateCard(id: id, title: "Antes da alteração externa")
        let backup = try Data(contentsOf: store.backupURL)
        let external = BoardSnapshot(cards: [KanbanCard(title: "Quadro externo válido")], boardTitle: "Outro quadro")
        let bytes = try JSONEncoder().encode(external)
        try bytes.write(to: store.documentURL, options: .atomic)
        try expect(store.updateCard(id: id, title: "Edição continua em memória"), "Mantém edição local em memória")
        try expect(store.saveError != nil && !store.flush(), "Detecta primary válido alterado externamente")
        try expect(try Data(contentsOf: store.documentURL) == bytes, "Não sobrescreve quadro externo válido")
        try expect(try Data(contentsOf: store.backupURL) == backup, "Não gira backup após detectar alteração externa")
        try expect(try quarantinedFiles(in: directory).isEmpty, "Não quarentena arquivo externo válido")
        let reopened = BoardStore(directory: directory)
        try expect(reopened.snapshot == external, "Reabertura explícita lê o quadro externo")
        let externalBackup = try JSONEncoder().encode(BoardSnapshot(boardTitle: "Cópia externa válida"))
        try externalBackup.write(to: reopened.backupURL, options: .atomic)
        try expect(!reopened.flush(), "Detecta backup válido alterado externamente")
        try expect(try Data(contentsOf: reopened.backupURL) == externalBackup, "Não sobrescreve backup externo válido")
        try expect(try Data(contentsOf: reopened.documentURL) == bytes, "Rejeição de backup não modifica primary")
        try FileManager.default.removeItem(at: reopened.backupURL)
        try expect(!reopened.flush() && !FileManager.default.fileExists(atPath: reopened.backupURL.path), "Não recria backup removido externamente")
        try FileManager.default.removeItem(at: reopened.documentURL)
        try expect(!reopened.flush() && !FileManager.default.fileExists(atPath: reopened.documentURL.path), "Não recria primary removido externamente")
    }

    @MainActor
    static func rootDirectoryProtection() throws {
        for sparse in [false, true] {
            let parent = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: parent) }
            let target = parent.appendingPathComponent("external", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let primary = target.appendingPathComponent("board.json")
            let backup = target.appendingPathComponent("board.backup.json")
            let primaryBytes = Data("Primary externo ilegível".utf8)
            try primaryBytes.write(to: primary)
            if sparse {
                let handle = try FileHandle(forWritingTo: primary)
                try handle.truncate(atOffset: UInt64(BoardStorageLimits.fileBytes + 1))
                try handle.close()
            }
            let backupBytes = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "Backup externo não deve ser lido")]))
            try backupBytes.write(to: backup)
            let linked = parent.appendingPathComponent("linked-root", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: target)
            var before = stat()
            try expect(lstat(primary.path, &before) == 0, "Registra identidade externa")
            let store = BoardStore(directory: linked)
            try expect(store.snapshot.cards.isEmpty && store.saveError != nil && store.lastSaved == nil, "Recusa root symlink antes de ler primary ou backup")
            try expect(!store.flush(), "Recusa salvamento em root symlink")
            _ = try unwrap(store.createCard())
            try expect(store.saveError != nil, "Edição não autoriza seguir o root symlink")
            try expect(Set(FileManager.default.contentsOfDirectory(atPath: target.path)) == Set(["board.json", "board.backup.json"]), "Não move nem cria entradas no destino externo")
            var after = stat()
            try expect(lstat(primary.path, &after) == 0 && before.st_ino == after.st_ino && before.st_size == after.st_size, "Primary externo mantém nome, inode e comprimento")
            let handle = try FileHandle(forReadingFrom: primary)
            let prefix = try handle.read(upToCount: primaryBytes.count)
            try handle.close()
            try expect(prefix == primaryBytes && Data(contentsOf: backup) == backupBytes, "Bytes externos permanecem intactos")
            try expect(try FileManager.default.destinationOfSymbolicLink(atPath: linked.path) == target.path, "Root link permanece intacto")

            let dotted = URL(fileURLWithPath: linked.path + "/./", isDirectory: true)
            let dottedStore = BoardStore(directory: dotted)
            try expect(dottedStore.snapshot.cards.isEmpty && dottedStore.saveError != nil && !dottedStore.flush(), "Normaliza final ./ antes de verificar symlink")
        }

        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let original = parent.appendingPathComponent("board-root", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let store = BoardStore(directory: original)
        let id = try unwrap(store.createCard())
        let originalData = try Data(contentsOf: store.documentURL)
        let retained = parent.appendingPathComponent("retained-root", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: retained)
        let external = parent.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        let badBytes = Data("Não renomear este arquivo externo".utf8)
        try badBytes.write(to: external.appendingPathComponent("board.json"))
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: external)
        try expect(store.updateCard(id: id, title: "Edição local preservada"), "Preserva edição em memória durante troca de root")
        try expect(store.saveError != nil && !store.flush(), "Root trocado por symlink suspende autosave")
        try expect(try Data(contentsOf: external.appendingPathComponent("board.json")) == badBytes, "Troca de root não toca bytes externos")
        try expect(try quarantinedFiles(in: external).isEmpty, "Troca de root não quarentena arquivo externo")
        try expect(try Data(contentsOf: retained.appendingPathComponent("board.json")) == originalData, "Root original também permanece intacto")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try badBytes.write(to: original.appendingPathComponent("board.json"))
        try expect(!store.flush() && Data(contentsOf: original.appendingPathComponent("board.json")) == badBytes, "Recusa root real substituído com outro inode")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.moveItem(at: retained, to: original)
        try expect(store.flush() && BoardStore(directory: original).card(id: id)?.title == "Edição local preservada", "Root original restaurado permite salvar edição pendente")
    }

    @MainActor
    static func privateLeafLinkIsolation() throws {
        let privateDirectory = try temporaryDirectory()
        let sharedDirectory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: privateDirectory)
            try? FileManager.default.removeItem(at: sharedDirectory)
        }
        let privateBoard = privateDirectory.appendingPathComponent("board.json")
        let secret = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "PRIVATE-SENTINEL")], boardTitle: "PRIVATE-BOARD"))
        try secret.write(to: privateBoard)
        let link = sharedDirectory.appendingPathComponent("board.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: privateBoard)
        let store = BoardStore(directory: sharedDirectory)
        try expect(store.snapshot.cards.isEmpty && !store.snapshot.boardTitle.contains("PRIVATE"), "Link de folha nunca importa quadro privado válido")
        try expect(!FileManager.default.fileExists(atPath: store.backupURL.path), "Link privado não produz backup compartilhado")
        try expect(try Data(contentsOf: privateBoard) == secret, "Alvo privado conserva bytes")
        try expect(try FileManager.default.contentsOfDirectory(atPath: privateDirectory.path) == ["board.json"], "Alvo privado conserva nome sem quarentena")
        let preserved = try quarantinedFiles(in: sharedDirectory)
        try expect(preserved.count == 1 && FileManager.default.destinationOfSymbolicLink(atPath: preserved[0].path) == privateBoard.path, "Preserva somente entrada do link")
        _ = try unwrap(store.createCard())
        try expect(store.saveError == nil && !FileManager.default.fileExists(atPath: store.backupURL.path), "Primeiro salvamento usa novo quadro, sem backup privado")
        try expect(store.flush() && !String(decoding: Data(contentsOf: store.backupURL), as: UTF8.self).contains("PRIVATE-SENTINEL"), "Backup posterior contém somente quadro novo")
        try expect(!String(decoding: Data(contentsOf: store.documentURL), as: UTF8.self).contains("PRIVATE-SENTINEL"), "Snapshot e JSON novo não revelam sentinela privada")
    }

    @MainActor
    static func parentPathTrust() throws {
        let fixture = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let external = fixture.appendingPathComponent("private-parent", isDirectory: true)
        let child = external.appendingPathComponent("board-root", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let secret = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "PRIVATE-PARENT-SENTINEL")]))
        try secret.write(to: child.appendingPathComponent("board.json"))
        try secret.write(to: child.appendingPathComponent("board.backup.json"))
        let linked = fixture.appendingPathComponent("parent-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: external)
        let store = BoardStore(directory: linked.appendingPathComponent("board-root", isDirectory: true))
        try expect(store.snapshot.cards.isEmpty && store.lastSaved == nil && !store.flush(), "Recusa link intermediário antes de ler primary ou backup")
        try expect(store.recoveryMessage == L("recovery.unsafeRoot") && store.recoveryTitleKey == "storage.alertTitle", "Aviso descreve recusa de caminho antes da leitura")
        try expect(try Data(contentsOf: child.appendingPathComponent("board.json")) == secret && Data(contentsOf: child.appendingPathComponent("board.backup.json")) == secret, "Link intermediário não toca bytes privados")
        try expect(Set(FileManager.default.contentsOfDirectory(atPath: child.path)) == Set(["board.json", "board.backup.json"]), "Link intermediário não renomeia nem cria arquivos privados")

        let missingRoot = fixture.appendingPathComponent("new-parent/new-root", isDirectory: true)
        let regular = BoardStore(directory: missingRoot)
        _ = try unwrap(regular.createCard())
        try expect(regular.saveError == nil && regular.flush(), "Cria cadeia nova por descritores e salva em root regular")
        for url in [missingRoot, missingRoot.deletingLastPathComponent()] {
            var metadata = stat()
            try expect(lstat(url.path, &metadata) == 0 && metadata.st_uid == geteuid() && metadata.st_mode & 0o7777 == 0o700, "Diretórios novos são privados")
        }
        try expect(BoardStore(directory: missingRoot).snapshot == regular.snapshot, "Root regular novo reabre")
        let alias = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent(fixture.lastPathComponent, isDirectory: true)
        let aliasStore = BoardStore(directory: alias)
        try expect(aliasStore.snapshot.cards.isEmpty && !aliasStore.flush() && aliasStore.recoveryMessage == L("recovery.unsafeRoot"), "Alias /tmp explícito também preserva evidência de link")
    }

    @MainActor
    static func privatePermissions() throws {
        for mode: mode_t in [0o755, 0o770, 0o777] {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let bytes = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "UNSAFE-ROOT-SENTINEL")]))
            let primary = root.appendingPathComponent("board.json")
            try bytes.write(to: primary)
            try expect(chmod(root.path, mode) == 0, "Configura root sintético")
            let store = BoardStore(directory: root)
            try expect(store.snapshot.cards.isEmpty && !store.flush() && store.recoveryMessage == L("recovery.unsafeRoot"), "Root configurado fora de 0700 é recusado antes da leitura")
            var metadata = stat()
            try expect(lstat(root.path, &metadata) == 0 && metadata.st_mode & 0o7777 == mode, "Não corrige silenciosamente permissões configuradas")
            try expect(try Data(contentsOf: primary) == bytes && FileManager.default.contentsOfDirectory(atPath: root.path) == ["board.json"], "Root inseguro conserva arquivos sem quarentena")
        }

        for (parentMode, allowed): (mode_t, Bool) in [(0o755, true), (0o777, false), (0o1777, true)] {
            let parent = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: parent) }
            let root = parent.appendingPathComponent("board-root", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let value = BoardSnapshot(cards: [KanbanCard(title: "PARENT-POLICY-SENTINEL")])
            let bytes = try JSONEncoder().encode(value)
            try bytes.write(to: root.appendingPathComponent("board.json"))
            try expect(chmod(parent.path, parentMode) == 0, "Configura pai sintético")
            let store = BoardStore(directory: root)
            try expect((store.snapshot == value) == allowed && store.flush() == allowed, "Pai com escrita estrangeira exige proteção sticky e proprietário seguro")
            if !allowed { try expect(try Data(contentsOf: root.appendingPathComponent("board.json")) == bytes, "Pai inseguro não modifica conteúdo") }
        }

        for mode: mode_t in [0o600, 0o644, 0o666] {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let value = BoardSnapshot(cards: [KanbanCard(title: "LEAF-POLICY-SENTINEL")])
            let primary = root.appendingPathComponent("board.json")
            let bytes = try JSONEncoder().encode(value)
            try bytes.write(to: primary)
            try expect(chmod(primary.path, mode) == 0, "Configura arquivo sintético")
            let store = BoardStore(directory: root)
            if mode == 0o666 {
                try expect(store.snapshot.cards.isEmpty && !store.flush() && store.recoveryMessage == L("recovery.unsafeRoot"), "Arquivo gravável por terceiros é recusado sem leitura")
                try expect(try Data(contentsOf: primary) == bytes && quarantinedFiles(in: root).isEmpty, "Arquivo inseguro não é movido nem alterado")
            } else {
                try expect(store.snapshot == value && store.flush(), "Importa arquivo atual 0600 ou 0644 dentro de root privada")
            }
        }
    }

    @MainActor
    static func accessControlLists() throws {
        for clause in ["everyone deny delete", "user:" + NSUserName() + " allow read,write,execute,delete"] {
            let root = try temporaryDirectory()
            defer { try? clearACL(root); try? FileManager.default.removeItem(at: root) }
            try setACL(root, clause: clause)
            let store = BoardStore(directory: root)
            let id = try unwrap(store.createCard())
            try expect(store.saveError == nil && store.flush() && BoardStore(directory: root).card(id: id) != nil, "ACL deny-only ou concessão somente ao usuário atual permanece compatível")
        }
        let emptyACLRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyACLRoot) }
        let emptyFD = open(emptyACLRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try expect(emptyFD >= 0, "Abre root para ACL vazia")
        defer { close(emptyFD) }
        let emptyACL = try unwrap(acl_init(0))
        defer { acl_free(UnsafeMutableRawPointer(emptyACL)) }
        try expect(acl_set_fd_np(emptyFD, emptyACL, ACL_TYPE_EXTENDED) == 0, "Configura ACL vazia válida")
        try expect(BoardStore(directory: emptyACLRoot).flush(), "ACL vazia é aceita")

        for unsafeLeaf in [false, true] {
            let root = try temporaryDirectory()
            let primary = root.appendingPathComponent("board.json")
            defer {
                try? clearACL(primary)
                try? clearACL(root)
                try? FileManager.default.removeItem(at: root)
            }
            let bytes = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "ACL-PRIVATE-SENTINEL")]))
            try bytes.write(to: primary)
            try setACL(unsafeLeaf ? primary : root, clause: unsafeLeaf ? "everyone allow read" : "everyone allow read,write,execute,file_inherit,directory_inherit")
            let store = BoardStore(directory: root)
            try expect(store.snapshot.cards.isEmpty && !store.flush() && store.recoveryMessage == L("recovery.unsafeRoot"), "ACL estrangeira bloqueia leitura mesmo com root 0700 ou arquivo 0644")
            try expect(try Data(contentsOf: primary) == bytes && FileManager.default.contentsOfDirectory(atPath: root.path) == ["board.json"], "ACL insegura conserva bytes e nomes sem alteração")
        }

        let parent = try temporaryDirectory()
        defer { try? clearACL(parent); try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("board-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let privateBytes = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "ACL-PARENT-SENTINEL")]))
        try privateBytes.write(to: root.appendingPathComponent("board.json"))
        try setACL(parent, clause: "everyone allow write,delete,delete_child")
        let parentStore = BoardStore(directory: root)
        try expect(parentStore.snapshot.cards.isEmpty && !parentStore.flush(), "ACL de escrita no pai também bloqueia o caminho")
        try expect(try Data(contentsOf: root.appendingPathComponent("board.json")) == privateBytes, "ACL do pai não expõe nem muda quadro")
        try clearACL(parent)
        try setACL(parent, clause: "everyone allow read,execute,file_inherit,directory_inherit")
        let newRoot = parent.appendingPathComponent("inherited-root", isDirectory: true)
        let inherited = BoardStore(directory: newRoot)
        _ = try unwrap(inherited.createCard())
        try expect(inherited.saveError != nil && !inherited.flush(), "Recusa ACL pública herdada antes de escrever conteúdo privado")
        try expect(try FileManager.default.contentsOfDirectory(atPath: newRoot.path).isEmpty, "Root nova com ACL insegura não recebe JSON nem backup")
    }

    @MainActor
    static func legacyDefaultPermissions() throws {
        for (mode, unsafeACL): (mode_t, Bool) in [(0o755, false), (0o777, false), (0o755, true)] {
            let root = try temporaryDirectory()
            defer { try? clearACL(root); try? FileManager.default.removeItem(at: root) }
            let bytes = Data("Preservar conteúdo durante migração".utf8)
            let marker = root.appendingPathComponent("marker.txt")
            try bytes.write(to: marker)
            try expect(chmod(root.path, mode) == 0, "Configura pasta legada sintética")
            if unsafeACL { try setACL(root, clause: "everyone allow read,write,execute") }
            let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            try expect(descriptor >= 0, "Abre descritor de migração sintética")
            defer { close(descriptor) }
            var migrated = false
            do { migrated = try BoardStore.tightenLegacyDefaultPermissions(descriptor: descriptor) }
            catch { try expect(mode != 0o755 || unsafeACL, "Migração segura 0755 deve ser aceita") }
            var metadata = stat()
            try expect(fstat(descriptor, &metadata) == 0, "Consulta modo depois da migração")
            try expect(migrated == (mode == 0o755 && !unsafeACL), "Migração restringe somente root legada 0755 segura")
            try expect(metadata.st_mode & 0o7777 == (migrated ? 0o700 : mode), "Migração recusada não corrige permissões ou ACLs")
            try expect(try Data(contentsOf: marker) == bytes && FileManager.default.contentsOfDirectory(atPath: root.path) == ["marker.txt"], "Migração preserva conteúdo e nomes")
            if migrated { try expect(!BoardStore.tightenLegacyDefaultPermissions(descriptor: descriptor), "Migração é idempotente") }
        }
    }

    @MainActor
    static func parentSwapProtection() throws {
        let fixture = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let parent = fixture.appendingPathComponent("original-parent", isDirectory: true)
        let root = parent.appendingPathComponent("board-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let store = BoardStore(directory: root)
        let id = try unwrap(store.createCard())
        let originalBytes = try Data(contentsOf: store.documentURL)
        let retained = fixture.appendingPathComponent("retained-parent", isDirectory: true)
        try FileManager.default.moveItem(at: parent, to: retained)
        let external = fixture.appendingPathComponent("external-parent", isDirectory: true)
        let externalRoot = external.appendingPathComponent("board-root", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let secret = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "SWAPPED-PRIVATE-SENTINEL")]))
        let externalBoard = externalRoot.appendingPathComponent("board.json")
        try secret.write(to: externalBoard)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: external)
        try expect(store.updateCard(id: id, title: "Edição pendente") && !store.flush(), "Troca de ancestral suspende IO e mantém edição em memória")
        try expect(try Data(contentsOf: externalBoard) == secret && FileManager.default.contentsOfDirectory(atPath: externalRoot.path) == ["board.json"], "Descritores fixados não seguem ancestral substituído")
        try expect(try Data(contentsOf: retained.appendingPathComponent("board-root/board.json")) == originalBytes, "Recusa não altera root original desconectada do caminho")
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.moveItem(at: retained, to: parent)
        try expect(store.flush() && BoardStore(directory: root).card(id: id)?.title == "Edição pendente", "Restaura ancestral original e salva edição pendente")
    }

    @MainActor
    static func interruptedInitialLoad() throws {
        for correction in ["remove", "corrupt", "secure"] {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let primary = root.appendingPathComponent("board.json")
            let backup = root.appendingPathComponent("board.backup.json")
            let value = BoardSnapshot(cards: [KanbanCard(title: "INITIAL-LOAD-SENTINEL")], boardTitle: "Quadro preservado")
            let primaryBytes = try JSONEncoder().encode(value)
            let backupBytes = try JSONEncoder().encode(BoardSnapshot(cards: [KanbanCard(title: "Backup anterior")]))
            try primaryBytes.write(to: primary)
            try backupBytes.write(to: backup)
            try expect(chmod(backup.path, 0o666) == 0, "Configura backup inseguro depois de primary válido")
            let store = BoardStore(directory: root)
            try expect(store.snapshot.cards.isEmpty && store.lastSaved == nil && store.recoveryMessage == L("recovery.unsafeRoot"), "Carga interrompida não assume fingerprint ou data de primary não exibido")
            if correction == "remove" {
                try FileManager.default.removeItem(at: backup)
            } else {
                try expect(chmod(backup.path, 0o600) == 0, "Corrige somente acesso do backup sintético")
                if correction == "corrupt" { try Data("Backup inválido depois da correção".utf8).write(to: backup) }
            }
            _ = try unwrap(store.createCard())
            try expect(store.saveError != nil && !store.flush(), "Instância vazia exige reabrir antes de gravar sobre primary existente")
            try expect(try Data(contentsOf: primary) == primaryBytes, "Corrigir backup sem reiniciar não sobrescreve quadro original")
            try expect(try quarantinedFiles(in: root).isEmpty, "Instância interrompida não move primary nem backup corrigido")
            let reopened = BoardStore(directory: root)
            try expect(reopened.snapshot == value && reopened.lastSaved != nil, "Reabrir instala quadro preservado como snapshot válido")
            let id = try unwrap(reopened.snapshot.cards.first?.id)
            try expect(reopened.updateCard(id: id, title: "Edição após reabrir") && reopened.saveError == nil, "Sessão reaberta aceita edição e salvamento")
            try expect(BoardStore(directory: root).card(id: id)?.title == "Edição após reabrir", "Salvamento depois de reabrir permanece funcional")
        }
    }

    static func setACL(_ url: URL, clause: String) throws {
        try chmodCommand(["+a", clause, url.path])
    }

    static func clearACL(_ url: URL) throws {
        try chmodCommand(["-N", url.path])
    }

    static func chmodCommand(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "Configura ACL somente em fixture sintética")
    }

    @MainActor
    static func rejectedFixture(_ data: Data, backup: BoardSnapshot, reason: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = directory.appendingPathComponent("board.json")
        try data.write(to: primary)
        try JSONEncoder().encode(backup).write(to: directory.appendingPathComponent("board.backup.json"))
        let store = BoardStore(directory: directory)
        try expect(store.snapshot == backup && store.recoveryMessage != nil, reason + ": recupera backup")
        let preserved = try quarantinedFiles(in: directory)
        try expect(preserved.count == 1 && Data(contentsOf: preserved[0]) == data, reason + ": preserva bytes rejeitados")
        try expect(store.flush() && Data(contentsOf: preserved[0]) == data, reason + ": não sobrescreve original preservado")
    }

    static func quarantinedFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".corrupt-") }
    }

    static func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("kanban-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw TestFailure(message: message) }
    }

    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure(message: "Valor ausente") }
        return value
    }

    struct TestFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { "FAIL: \(message)" }
    }
}
