import AppKit

@MainActor private var translatingNativeMenus = false

/// Localize the menu headings only. System commands keep AppKit's titles and validation.
@MainActor
func localizeNativeMenus() {
    guard !translatingNativeMenus, let mainMenu = NSApp.mainMenu else { return }
    translatingNativeMenus = true
    defer { translatingNativeMenus = false }
    for item in mainMenu.items.dropFirst() {
        guard let submenu = item.submenu else { continue }
        let selectors = Set(submenu.items.compactMap { $0.action.map(NSStringFromSelector) })
        let key: String?
        if submenu === NSApp.windowsMenu || selectors.contains("performMiniaturize:") { key = "menu.window" }
        else if submenu === NSApp.helpMenu { key = "menu.help" }
        else if selectors.contains("cut:") || selectors.contains("copy:") { key = "menu.edit" }
        else if selectors.contains("performClose:") || selectors.contains("closeWindow:") { key = "menu.file" }
        else if selectors.contains("toggleFullScreen:") { key = "menu.view" }
        else {
            let candidate = AppLocalization.shared.nativeMenuKey(for: item.title)
                ?? AppLocalization.shared.nativeMenuKey(for: submenu.title)
            key = candidate.flatMap { ["menu.file", "menu.edit", "menu.view", "menu.window", "menu.help"].contains($0) ? $0 : nil }
        }
        if let key {
            let title = L(key)
            if item.title != title { item.title = title }
            if submenu.title != title { submenu.title = title }
        }
    }
}
