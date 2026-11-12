// Store.swift — central app state. Credentials: Xtream passwords live ONLY
// in the iOS Keychain (never in UserDefaults, never in chat/memory).
// Everything else (accounts list, favorites, renames, orders, settings)
// is plain UserDefaults JSON, same keys as the Android prefs where it
// matters (ord_<key> saved orders, ser_status overrides).

import Foundation
import SwiftUI
import Security

// MARK: - Keychain (passwords only)

enum Keychain {
    static let service = "com.maro.iptv"

    static func savePassword(_ password: String, for accountId: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "xt-pass-\(accountId)"
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func password(for accountId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "xt-pass-\(accountId)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for accountId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "xt-pass-\(accountId)"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Store

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    // MARK: Settings
    @AppStorage("app_lang") var languageRaw: String = "ar"
    var language: AppLanguage {
        get { AppLanguage(rawValue: languageRaw) ?? .arabic }
        set { languageRaw = newValue.rawValue }
    }
    @AppStorage("dub_enabled") var dubbingEnabled = false
    @AppStorage("app_version") var appVersion = "1.0"

    // MARK: Accounts
    @Published private(set) var accounts: [XtreamAccount] = []
    @Published var currentAccountId: String?
    var currentAccount: XtreamAccount? { accounts.first { $0.id == currentAccountId } }

    // MARK: Live data
    @Published var categories: [String: String] = [:]   // id -> name
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var loadError: String?

    // MARK: Library data
    @Published var vodCategories: [String: String] = [:]
    @Published var seriesCategories: [String: String] = [:]
    @Published var movies: [VodItem] = []
    @Published var series: [VodItem] = []

    // MARK: Private list / renames / hidden / orders (UserDefaults JSON)
    private let defaults = UserDefaults.standard

    var favorites: Set<String> {
        get { Set(defaults.stringArray(forKey: "favorites") ?? []) }
        set { defaults.set(Array(newValue), forKey: "favorites") }
    }
    var renames: [String: String] {
        get { defaults.dictionary(forKey: "renames") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "renames") }
    }
    var hidden: Set<String> {
        get { Set(defaults.stringArray(forKey: "hidden") ?? []) }
        set { defaults.set(Array(newValue), forKey: "hidden") }
    }
    var seriesStatusOverrides: [String: String] {
        get { defaults.dictionary(forKey: "ser_status") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "ser_status") }
    }

    init() {
        loadAccounts()
        currentAccountId = defaults.string(forKey: "current_account")
    }

    // MARK: - Accounts

    private func loadAccounts() {
        if let data = defaults.data(forKey: "accounts"),
           let list = try? JSONDecoder().decode([XtreamAccount].self, from: data) {
            accounts = list
        }
        // Built-in free account is always present (Android id=builtin-free).
        if !accounts.contains(where: { $0.id == "builtin-free" }) {
            accounts.append(XtreamAccount(id: "builtin-free", kind: .free,
                                          name: L("📺 قنوات مجانية", "📺 Free channels"),
                                          server: XtreamAPI.freeM3UURL, username: ""))
        }
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: "accounts")
        }
    }

    func password(for account: XtreamAccount?) -> String? {
        guard let account = account else { return nil }
        return Keychain.password(for: account.id)
    }

    func addAccount(_ account: XtreamAccount, password: String?) {
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        if let password = password { Keychain.savePassword(password, for: account.id) }
        saveAccounts()
        currentAccountId = account.id
        defaults.set(account.id, forKey: "current_account")
    }

    func removeAccount(_ account: XtreamAccount) {
        accounts.removeAll { $0.id == account.id }
        Keychain.deletePassword(for: account.id)
        saveAccounts()
        if currentAccountId == account.id {
            currentAccountId = accounts.first?.id
            defaults.set(currentAccountId, forKey: "current_account")
        }
    }

    func selectAccount(_ account: XtreamAccount) {
        currentAccountId = account.id
        defaults.set(account.id, forKey: "current_account")
        Task { await loadLive() }
    }

    // MARK: - Live loading

    func loadLive() async {
        guard let account = currentAccount else { return }
        isLoading = true
        loadError = nil
        do {
            switch account.kind {
            case .xtream:
                let pw = password(for: account) ?? ""
                let (cats, chans) = try await XtreamAPI.fetchLive(account: account, password: pw)
                categories = cats
                channels = chans.filter { !hidden.contains($0.id) }
            case .m3u, .free:
                let (cats, chans) = try await XtreamAPI.fetchM3U(urlString: account.server)
                categories = cats
                channels = chans.filter { !hidden.contains($0.id) }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Library loading

    func loadLibrary() async {
        guard let account = currentAccount, account.isXtream else {
            // M3U / free account: no provider VOD library (Android shows
            // only the free public-domain sections; wired in LibraryView).
            movies = []
            series = []
            return
        }
        let pw = password(for: account) ?? ""
        do {
            async let vc = XtreamAPI.fetchVodCategories(account: account, password: pw)
            async let sc = XtreamAPI.fetchSeriesCategories(account: account, password: pw)
            async let mv = XtreamAPI.fetchVodStreams(account: account, password: pw)
            async let sr = XtreamAPI.fetchSeries(account: account, password: pw)
            vodCategories = try await vc
            seriesCategories = try await sc
            movies = try await mv
            series = try await sr
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Lists

    /// Channels of one category, in server order, with the user's saved
    /// custom order applied (v2: {"v":2,"ids":[...]}).
    func channels(forCategory catId: String) -> [Channel] {
        let list = channels.filter { $0.catId == catId }
        return applySavedOrder(list, key: catId)
    }

    /// «🛰️ باقة النايل سات» — every Nilesat channel, grouped in the
    /// Android v4.20 order (cartoon, NatGeo, AR movies, AR series,
    /// foreign movies, foreign series, news, sports, rest).
    var nilesatChannels: [Channel] {
        let list = channels.filter { $0.isNilesat }
        return applySavedOrder(groupNilesat(list), key: "NILE")
    }

    var favoriteChannels: [Channel] {
        channels.filter { favorites.contains($0.id) }
    }

    /// Saved order for a list key; legacy v1 NILE orders are discarded
    /// once (Android v4.21: a v1 NILE order is a pre-grouping server
    /// snapshot and would undo the grouping).
    func applySavedOrder(_ list: [Channel], key: String) -> [Channel] {
        guard let raw = defaults.string(forKey: "ord_\(key)"),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["v"] as? Int) == 2,
              let ids = json["ids"] as? [String] else {
            if key == "NILE" { defaults.removeObject(forKey: "ord_NILE") }
            return list
        }
        var byId = [String: Channel]()
        for ch in list { byId[ch.id] = ch }
        var out = [Channel]()
        for id in ids { if let ch = byId[id] { out.append(ch); byId.removeValue(forKey: id) } }
        out.append(contentsOf: byId.values)
        return out
    }

    func moveChannel(_ channel: Channel, in listKey: String, direction: Int) {
        var list = listKey == "NILE" ? nilesatChannels : channels(forCategory: listKey)
        guard let idx = list.firstIndex(of: channel) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0 && newIdx < list.count else { return }
        list.swapAt(idx, newIdx)
        saveOrder(list.map { $0.id }, key: listKey)
        objectWillChange.send()
    }

    func moveChannel(_ channel: Channel, in listKey: String, to position: Int) {
        var list = listKey == "NILE" ? nilesatChannels : channels(forCategory: listKey)
        guard let idx = list.firstIndex(of: channel) else { return }
        let item = list.remove(at: idx)
        let pos = max(0, min(position - 1, list.count))
        list.insert(item, at: pos)
        saveOrder(list.map { $0.id }, key: listKey)
        objectWillChange.send()
    }

    func resetOrder(key: String) {
        defaults.removeObject(forKey: "ord_\(key)")
        objectWillChange.send()
    }

    private func saveOrder(_ ids: [String], key: String) {
        let json: [String: Any] = ["v": 2, "ids": ids]
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let s = String(data: data, encoding: .utf8) {
            defaults.set(s, forKey: "ord_\(key)")
        }
    }

    func customName(for channelId: String) -> String? { renames[channelId] }

    func rename(_ channel: Channel, to name: String) {
        var r = renames
        if name.isEmpty || name == channel.name { r.removeValue(forKey: channel.id) }
        else { r[channel.id] = name }
        renames = r
        objectWillChange.send()
    }

    func hide(_ channel: Channel) {
        var h = hidden
        h.insert(channel.id)
        hidden = h
        channels.removeAll { $0.id == channel.id }
    }

    func toggleFavorite(_ channel: Channel) {
        var f = favorites
        if f.contains(channel.id) { f.remove(channel.id) } else { f.insert(channel.id) }
        favorites = f
        objectWillChange.send()
    }

    // MARK: - Search

    /// Live suggestions: score 2 (exact canonical substring) first, then
    /// score 1 (fuzzy), capped at 30 — Android v4.14/v4.19.
    func suggestions(for query: String, in list: [Channel]) -> [Channel] {
        let qSmart = smartFold(query)
        let qToks = smartTokens(qSmart)
        guard !qSmart.isEmpty else { return [] }
        var exact = [Channel]()
        var fuzzy = [Channel]()
        for ch in list {
            let score = smartMatchScore(nameSmart: ch.smart, nameToks: ch.smartToks, qSmart: qSmart, qToks: qToks)
            if score == 2 { exact.append(ch) }
            else if score == 1 { fuzzy.append(ch) }
            if exact.count + fuzzy.count >= 30 { break }
        }
        return Array((exact + fuzzy).prefix(30))
    }

    func searchChannels(_ query: String, in list: [Channel]) -> [Channel] {
        suggestions(for: query, in: list)
    }

    // MARK: - Series status (Android v4.5)

    func seriesStatus(_ item: VodItem, lastEpisodeAddedMs: TimeInterval = 0) -> SeriesStatus {
        if let ov = seriesStatusOverrides[foldAr(item.name)], let s = SeriesStatus(rawValue: ov) { return s }
        let cf = foldAr(seriesCategories[item.catId])
        if cf.contains("منتهي") || cf.contains("مكتمل") { return .done }
        if cf.contains("متوقف") { return .stopped }
        if lastEpisodeAddedMs > 0 {
            let gapDays = (Date().timeIntervalSince1970 - lastEpisodeAddedMs) / 86400
            if gapDays > 180 { return .stopped }
            return .ongoing
        }
        return .ongoing
    }

    func setSeriesStatus(_ item: VodItem, _ status: SeriesStatus?) {
        var ov = seriesStatusOverrides
        if let status = status { ov[foldAr(item.name)] = status.rawValue }
        else { ov.removeValue(forKey: foldAr(item.name)) }
        seriesStatusOverrides = ov
        objectWillChange.send()
    }

    /// Anime/series list with One Piece pinned first in EVERY view (v4.5).
    func pinnedSeries(_ items: [VodItem]) -> [VodItem] {
        let first = items.filter { $0.isOnePiece }
        let rest = items.filter { !$0.isOnePiece }
        return first + rest
    }
}
