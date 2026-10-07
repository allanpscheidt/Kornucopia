import Foundation

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
        print("PASS: 11 grupos de testes do modelo e da persistência")
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
