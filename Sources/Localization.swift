import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case portuguese = "pt-BR"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"

    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .portuguese: return "Português (Brasil)"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .japanese: return "日本語"
        }
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let base = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first
            switch base {
            case "pt": return .portuguese
            case "en": return .english
            case "es": return .spanish
            case "fr": return .french
            case "ja": return .japanese
            default: continue
            }
        }
        return .english
    }
}

@MainActor
enum AppPreferences {
    static let scopeID: String = {
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment["KORNUCOPIA_PREFERENCES_SUITE"], !suite.isEmpty { return stableID(suite) }
        if let directory = environment["KORNUCOPIA_DATA_DIR"] ?? environment["KANBAN_DATA_DIR"], !directory.isEmpty {
            return stableID(directory)
        }
        return "personal"
    }()

    static let defaults: UserDefaults = {
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment["KORNUCOPIA_PREFERENCES_SUITE"], !suite.isEmpty,
           let defaults = UserDefaults(suiteName: suite) { return defaults }
        if scopeID != "personal", let defaults = UserDefaults(suiteName: "net.allanpscheidt.kornucopia.qa." + scopeID) {
            return defaults
        }
        return .standard
    }()

    static func tutorialExpanded(for column: String, defaults override: UserDefaults? = nil) -> Bool {
        let preferences = override ?? defaults
        let key = "tutorial." + column
        return preferences.object(forKey: key) == nil ? true : preferences.bool(forKey: key)
    }

    private static func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    static let automatic = "system"
    @Published private(set) var selection: String
    @Published private(set) var language: AppLanguage

    private let defaults: UserDefaults
    private let systemLanguages: [String]
    private let catalogs: [AppLanguage: [String: String]]
    var systemLanguage: AppLanguage { AppLanguage.resolve(preferredLanguages: systemLanguages) }

    init(defaults: UserDefaults? = nil,
         preferredLanguages: [String] = Locale.preferredLanguages,
         catalogDirectory: URL? = nil) {
        self.defaults = defaults ?? AppPreferences.defaults
        self.systemLanguages = preferredLanguages
        let saved = self.defaults.string(forKey: "language") ?? Self.automatic
        selection = AppLanguage(rawValue: saved) == nil ? Self.automatic : saved
        language = AppLanguage(rawValue: saved) ?? AppLanguage.resolve(preferredLanguages: preferredLanguages)
        let directory = catalogDirectory ?? Self.resourceDirectory()
        var loaded: [AppLanguage: [String: String]] = [:]
        for language in AppLanguage.allCases {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(language.rawValue + ".json")),
               let catalog = try? JSONDecoder().decode([String: String].self, from: data) {
                loaded[language] = catalog
            }
        }
        catalogs = loaded
    }

    func select(_ value: String) {
        guard value == Self.automatic || AppLanguage(rawValue: value) != nil else { return }
        selection = value
        language = AppLanguage(rawValue: value) ?? systemLanguage
        defaults.set(value, forKey: "language")
    }

    func text(_ key: String, _ values: [String: String] = [:]) -> String {
        let template = catalogs[language]?[key] ?? catalogs[.english]?[key] ?? catalogs[.portuguese]?[key] ?? key
        return Self.format(template, values: values)
    }

    func cardCount(_ count: Int) -> String {
        text(count == 1 ? "board.count.one" : "board.count.other", ["count": String(count)])
    }

    func nativeMenuKey(for title: String) -> String? {
        let normalized = title.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").lowercased()
        let extraKeys: Set<String> = ["action.newCard", "action.undo", "action.redo", "settings.title", "board.search"]
        for catalog in catalogs.values {
            if let pair = catalog.first(where: { ($0.key.hasPrefix("menu.") || extraKeys.contains($0.key)) && $0.value.lowercased() == normalized }) {
                return pair.key
            }
        }
        // AppKit supplies these standard variants before command wrappers exist.
        return ["fechar": "menu.closeWindow", "close": "menu.closeWindow", "fechar todas": "menu.closeAll",
                "close all": "menu.closeAll", "mostrar tudo": "menu.showAll", "bring all to front": "menu.bringAllToFront",
                "entrar em tela cheia": "menu.fullScreen", "sair da tela cheia": "menu.fullScreen",
                "enter full screen": "menu.fullScreen", "exit full screen": "menu.fullScreen"][normalized]
    }

    /// Replaces only placeholders in the original template; user text remains literal.
    static func format(_ template: String, values: [String: String]) -> String {
        guard let expression = try? NSRegularExpression(pattern: "\\{([A-Za-z][A-Za-z0-9_]*)\\}") else { return template }
        let mutable = NSMutableString(string: template)
        let matches = expression.matches(in: template, range: NSRange(template.startIndex..., in: template))
        for match in matches.reversed() {
            guard let nameRange = Range(match.range(at: 1), in: template) else { continue }
            let name = String(template[nameRange])
            if let value = values[name] { mutable.replaceCharacters(in: match.range, with: value) }
        }
        return mutable as String
    }

    private static func resourceDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["KORNUCOPIA_LOCALIZATION_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let resources = Bundle.main.resourceURL {
            let directory = resources.appendingPathComponent("Localization", isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) { return directory }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Resources/Localization", isDirectory: true)
    }
}

@MainActor
func L(_ key: String, _ values: [String: String] = [:]) -> String {
    AppLocalization.shared.text(key, values)
}
