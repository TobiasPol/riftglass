import Foundation

/// Champion, item, rune and augment names follow the app's language (English, or German when macOS
/// prefers it), so the UI never mixes languages.
enum GameDataLocale {
    /// The localization the app runs in (`en` or `de`, from the string catalog).
    static var isGerman: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("de") == true
    }

    /// Data Dragon locale folder.
    static var dataDragon: String {
        isGerman ? "de_DE" : "en_US"
    }

    /// CommunityDragon locale folder (`default` = en_US).
    static var communityDragon: String {
        isGerman ? "de_de" : "default"
    }
}
