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
        print("PASS: 19 grupos de testes do modelo, da persistência e dos limites de armazenamento")
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
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kanban-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
