import Foundation

@main
struct LocalizationTests {
    @MainActor
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Localization", isDirectory: true)
        let languages = AppLanguage.allCases
        var catalogs: [AppLanguage: [String: String]] = [:]
        for language in languages {
            let data = try Data(contentsOf: directory.appendingPathComponent(language.rawValue + ".json"))
            catalogs[language] = try JSONDecoder().decode([String: String].self, from: data)
        }
        let english = try unwrap(catalogs[.english])
        let keys = Set(english.keys)
        try expect(keys.count >= 140, "Complete UI catalogs")
        for language in languages {
            let catalog = try unwrap(catalogs[language])
            try expect(Set(catalog.keys) == keys, "Identical keys for \(language.rawValue)")
            for key in keys {
                let value = try unwrap(catalog[key])
                try expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Nonempty \(key)")
                try expect(placeholders(value) == placeholders(english[key]!), "Same placeholders for \(key)")
                let lower = value.lowercased()
                try expect(!lower.contains("post-it") && !lower.contains("post it") && !lower.contains("gravity"), "Generic wording")
            }
            for column in ["backlog", "doing", "review", "done"] {
                for suffix in ["title", "subtitle", "tutorial.title", "tutorial.step1", "tutorial.step2", "tutorial.step3", "tutorial.next"] {
                    try expect(catalog["column.\(column).\(suffix)"] != nil, "Tutorial contract")
                }
            }
        }
        try expect(placeholders(english["column.doing.tutorial.step1"]!) == ["limit"], "Tutorial uses configurable limit")
        try expect(AppLanguage.resolve(preferredLanguages: ["pt-PT"]) == .portuguese, "Portuguese detection")
        try expect(AppLanguage.resolve(preferredLanguages: ["en-GB"]) == .english, "English detection")
        try expect(AppLanguage.resolve(preferredLanguages: ["es-MX"]) == .spanish, "Spanish detection")
        try expect(AppLanguage.resolve(preferredLanguages: ["fr_CA"]) == .french, "French detection")
        try expect(AppLanguage.resolve(preferredLanguages: ["ja-JP"]) == .japanese, "Japanese detection")
        try expect(AppLanguage.resolve(preferredLanguages: ["de-DE", "fr-FR"]) == .french, "Next supported language")
        try expect(AppLanguage.resolve(preferredLanguages: ["de-DE"]) == .english, "English fallback")

        let suite = "net.allanpscheidt.kornucopia.localization-tests." + UUID().uuidString
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localizer = AppLocalization(defaults: defaults, preferredLanguages: ["ja-JP"], catalogDirectory: directory)
        try expect(AppPreferences.tutorialExpanded(for: "doing", defaults: defaults), "Tutorial starts expanded")
        defaults.set(false, forKey: "tutorial.doing")
        try expect(!AppPreferences.tutorialExpanded(for: "doing", defaults: defaults), "Collapsed tutorial preference is preserved")
        try expect(localizer.selection == "system" && localizer.language == .japanese, "Automatic selection")
        for language in languages {
            localizer.select(language.rawValue)
            try expect(localizer.language == language, "Selectable language")
            try expect(localizer.text("column.doing.title") == catalogs[language]?["column.doing.title"], "Localized label")
            let tutorial = localizer.text("column.doing.tutorial.step1", ["limit": "7"])
            try expect(tutorial.contains("7") && !tutorial.contains("{limit}"), "Named placeholder")
        }
        localizer.select("es")
        try expect(localizer.nativeMenuKey(for: "Arquivo") == "menu.file", "AppKit root menu lookup")
        try expect(localizer.nativeMenuKey(for: "Janela") == "menu.window", "Window menu lookup")
        try expect(localizer.nativeMenuKey(for: "設定") == "settings.title", "Native command label lookup")
        try expect(localizer.nativeMenuKey(for: "Fechar Todas") == "menu.closeAll", "AppKit close-all variant")
        let reopened = AppLocalization(defaults: defaults, preferredLanguages: ["ja-JP"], catalogDirectory: directory)
        try expect(reopened.language == .spanish && reopened.selection == "es", "Language preference survives reopening")
        reopened.select("system")
        try expect(reopened.language == .japanese, "Automatic language resumes")
        reopened.select("invalid")
        try expect(reopened.selection == "system", "Invalid selection is ignored")
        try expect(AppLocalization.format("{title}, {column}", values: ["title": "Original {column} 日本語", "column": "Doing"]) == "Original {column} 日本語, Doing", "User content remains literal")
        try expect(AppLocalization.format("{limit}/{count}", values: ["limit": "3", "count": "2"]) == "3/2", "Multiple placeholders")
        try expect(localizer.cardCount(1) != localizer.cardCount(2), "Card count formatting")
        print("PASS: five localization catalogs, tutorial contract, placeholders, detection and isolated preferences")
    }

    static func placeholders(_ value: String) -> Set<String> {
        let expression = try! NSRegularExpression(pattern: "\\{([A-Za-z][A-Za-z0-9_]*)\\}")
        return Set(expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[range])
        })
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw TestFailure(message: message) }
    }

    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure(message: "Missing value") }
        return value
    }

    struct TestFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { "FAIL: " + message }
    }
}
