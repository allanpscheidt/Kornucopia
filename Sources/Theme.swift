import SwiftUI
import AppKit

enum Theme {
    static let canvas = Color(hex: 0xF4F8F7)
    static let column = Color(hex: 0xE7F0ED)
    static let ink = Color(hex: 0x17243C)
    static let secondary = Color(hex: 0x566578)
    static let line = Color(hex: 0xCCDCD7)
    static let accent = Color(hex: 0x147D76)
    static let strong = Color(hex: 0x11645F)
    static let night = Color(hex: 0x0B252B)
    static let warning = Color(hex: 0x8A5113)
    static let logo: NSImage = {
        guard let url = Bundle.main.url(forResource: "Cornucopia", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }()
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension NoteColor {
    var paper: Color {
        switch self {
        case .yellow: return Color(hex: 0xF6E8A9)
        case .blue: return Color(hex: 0xD5E7EF)
        case .purple: return Color(hex: 0xE4DDF0)
        case .green: return Color(hex: 0xD9E8CF)
        case .rose: return Color(hex: 0xF2DBD5)
        }
    }
    var mark: Color {
        switch self {
        case .yellow: return Color(hex: 0xAD811D)
        case .blue: return Color(hex: 0x4F809B)
        case .purple: return Color(hex: 0x80679F)
        case .green: return Color(hex: 0x648451)
        case .rose: return Color(hex: 0xA76C5F)
        }
    }
}

extension KanbanColumn {
    var dot: Color {
        switch self {
        case .backlog: return Color(hex: 0xAD811D)
        case .doing: return Color(hex: 0x4F809B)
        case .review: return Color(hex: 0x826AA4)
        case .done: return Color(hex: 0x4E8068)
        }
    }
    var emptySymbol: String {
        switch self {
        case .backlog: return "tray"
        case .doing: return "pencil.tip"
        case .review: return "text.magnifyingglass"
        case .done: return "checkmark"
        }
    }
    @MainActor var emptyTitle: String { L("column." + rawValue + ".emptyTitle") }
    @MainActor var emptyHelp: String { L("column." + rawValue + ".emptyHelp") }
}
