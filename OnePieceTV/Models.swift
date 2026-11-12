// Models.swift — data models + bilingual strings (Arabic default,
// English toggle), mirroring the Android app.

import Foundation

// MARK: - Localization

enum AppLanguage: String, Codable { case arabic = "ar", english = "en" }

/// L("arabic", "english") — the Android app's L() helper.
/// Reads UserDefaults directly (not via AppStore) so it is callable
/// from any isolation context, including error descriptions.
func L(_ ar: String, _ en: String) -> String {
    UserDefaults.standard.string(forKey: "app_lang") == "en" ? en : ar
}

// MARK: - Accounts

enum AccountKind: String, Codable { case xtream, m3u, free }

struct XtreamAccount: Codable, Identifiable, Equatable {
    var id: String
    var kind: AccountKind
    var name: String
    var server: String      // Xtream base URL (no trailing slash) or M3U URL
    var username: String
    // NOTE: the password is NEVER stored in this struct's UserDefaults copy.
    // It lives in the Keychain under "xt-pass-<id>".

    var isXtream: Bool { kind == .xtream }
}

// MARK: - Channels

struct Channel: Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var catId: String
    var categoryName: String
    var logo: String

    // Flags computed once at load (Android computeFlags()).
    var isEgyptian = false
    var isCartoon = false
    var isNilesat = false
    var smart = ""
    var smartToks: [String] = []

    /// Display name after the user's rename (nil = original name).
    /// Reads UserDefaults directly so it works from any context.
    var displayName: String {
        (UserDefaults.standard.dictionary(forKey: "renames") as? [String: String])?[id] ?? name
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool { lhs.id == rhs.id }
}

// MARK: - VOD

struct VodItem: Identifiable, Equatable {
    var id: String
    var name: String
    var cover: String
    var year: String
    var rating: String
    var plot: String
    var ext: String
    var catId: String
    var type: String        // "m" movie, "s" series, "a" archive (public domain)
    var addedMs: TimeInterval = 0
    // The Xtream account this item came from (nil = current account).
    var accServer: String?
    var accUser: String?
    var accPass: String?

    static func == (lhs: VodItem, rhs: VodItem) -> Bool { lhs.id == rhs.id && lhs.type == rhs.type }

    var isOnePiece: Bool {
        let f = foldAr(name)
        return f.contains("one piece") || f.contains("ون بيس")
    }
}

struct Episode: Identifiable {
    var id: String
    var title: String
    var season: String
    var ext: String
    var addedMs: TimeInterval = 0
    var epNum: Int = 0
    var accServer: String?
    var accUser: String?
    var accPass: String?
}

struct SeriesInfo {
    var info: [String: String] = [:]
    var seasons: [String: [Episode]] = [:]   // season number -> episodes
    var cover: String = ""
    var plot: String = ""
    var rating: String = ""
    var year: String = ""
}

// MARK: - Anime / series status

enum SeriesStatus: String { case ongoing = "ONGOING", done = "DONE", stopped = "STOPPED" }

let toonCatKeys = ["cartoon", "anime", "animation", "كرتون", "كارتون", "أنمي", "انمي"]
let toonNameKeys = [
    "cartoon", "anime", "animation", "كرتون", "كارتون", "أنمي", "انمي",
    "ون بيس", "one piece", "naruto", "dragon ball", "attack on titan",
    "demon slayer", "jujutsu", "bleach", "pokemon", "digimon",
    "one punch", "hunter", "death note"
]

func isToonCategory(_ catName: String?) -> Bool {
    guard let catName = catName else { return false }
    let f = foldAr(catName)
    return toonCatKeys.contains { f.contains(foldAr($0)) }
}

func isToonName(_ name: String?) -> Bool {
    guard let name = name else { return false }
    let f = foldAr(name)
    if f.isEmpty { return false }
    return toonNameKeys.contains { f.contains(foldAr($0)) }
}

// MARK: - EPG

struct EpgEntry: Identifiable {
    var id: String { title + start }
    var title: String
    var start: String   // "HH:mm"
    var end: String
    var description: String
}
