// XtreamAPI.swift — Xtream Codes player_api.php client + M3U parser.
// Mirrors the Android fetch code (MainActivity.java): same endpoints,
// same stream-URL shapes, same #EXTINF parsing.

import Foundation

enum XtreamError: LocalizedError {
    case network(Error)
    case badResponse
    case emptyPlaylist
    case authFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .network(let e): return e.localizedDescription
        case .badResponse: return L("رد غير صالح من السيرفر", "Bad response from server")
        case .emptyPlaylist: return L("القائمة فاضية", "Empty playlist")
        case .authFailed: return L("بيانات الدخول غلط", "Wrong login details")
        case .invalidURL: return L("الرابط مش صحيح", "Invalid URL")
        }
    }
}

struct XtreamAPI {
    static let freeM3UURL = "https://iptv-org.github.io/iptv/index.m3u"

    // MARK: - HTTP

    private static func get(_ urlString: String, timeout: TimeInterval = 15) async throws -> Data {
        guard let url = URL(string: urlString) else { throw XtreamError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("OnePieceTV-iOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw XtreamError.badResponse
            }
            return data
        } catch let e as XtreamError { throw e }
        catch { throw XtreamError.network(error) }
    }

    private static func getJSON(_ urlString: String, timeout: TimeInterval = 15) async throws -> Any {
        let data = try await get(urlString, timeout: timeout)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func base(server: String, user: String, pass: String) -> String {
        let srv = server.hasSuffix("/") ? String(server.dropLast()) : server
        let u = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let p = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
        return "\(srv)/player_api.php?username=\(u)&password=\(p)"
    }

    // MARK: - Live

    /// Returns (categories, channels). Categories: id -> name.
    static func fetchLive(account: XtreamAccount, password: String) async throws -> ([String: String], [Channel]) {
        let b = base(server: account.server, user: account.username, pass: password)
        async let catsData = getJSON(b + "&action=get_live_categories")
        async let streamsData = getJSON(b + "&action=get_live_streams")
        let catsJSON = try await catsData
        let streamsJSON = try await streamsData

        var cats = [String: String]()
        if let arr = catsJSON as? [[String: Any]] {
            for o in arr {
                if let id = o["category_id"] as? String, let name = o["category_name"] as? String {
                    cats[id] = name
                }
            }
        }
        var channels = [Channel]()
        if let arr = streamsJSON as? [[String: Any]] {
            for o in arr {
                guard let sid = o["stream_id"] as? String ?? (o["stream_id"] as? NSNumber)?.stringValue,
                      let name = o["name"] as? String else { continue }
                let catId = (o["category_id"] as? String) ?? (o["category_id"] as? NSNumber)?.stringValue ?? ""
                let logo = o["stream_icon"] as? String ?? ""
                let url = "\(account.server)/live/\(account.username)/\(password)/\(sid).ts"
                var ch = Channel(id: "xt:\(sid)", name: name, url: url, catId: catId,
                                 categoryName: cats[catId] ?? catId, logo: logo)
                computeFlags(&ch)
                channels.append(ch)
            }
        }
        return (cats, channels)
    }

    /// Short EPG for one live stream (Android get_short_epg).
    static func fetchShortEPG(account: XtreamAccount, password: String, streamId: String) async throws -> [EpgEntry] {
        let b = base(server: account.server, user: account.username, pass: password)
        let sid = streamId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? streamId
        let json = try await getJSON(b + "&action=get_short_epg&stream_id=\(sid)")
        var out = [EpgEntry]()
        if let root = json as? [String: Any], let arr = root["epg_listings"] as? [[String: Any]] {
            for o in arr {
                out.append(EpgEntry(
                    title: o["title"] as? String ?? "",
                    start: o["start"] as? String ?? "",
                    end: o["end"] as? String ?? "",
                    description: o["description"] as? String ?? ""))
            }
        }
        return out
    }

    // MARK: - VOD (movies + series)

    static func fetchVodCategories(account: XtreamAccount, password: String) async throws -> [String: String] {
        let b = base(server: account.server, user: account.username, pass: password)
        let json = try await getJSON(b + "&action=get_vod_categories")
        var cats = [String: String]()
        if let arr = json as? [[String: Any]] {
            for o in arr {
                if let id = o["category_id"] as? String, let name = o["category_name"] as? String { cats[id] = name }
            }
        }
        return cats
    }

    static func fetchVodStreams(account: XtreamAccount, password: String, categoryId: String? = nil) async throws -> [VodItem] {
        let b = base(server: account.server, user: account.username, pass: password)
        var url = b + "&action=get_vod_streams"
        if let cat = categoryId { url += "&category_id=\(cat)" }
        let json = try await getJSON(url)
        var out = [VodItem]()
        if let arr = json as? [[String: Any]] {
            for o in arr {
                guard let id = (o["stream_id"] as? String) ?? (o["stream_id"] as? NSNumber)?.stringValue,
                      let name = o["name"] as? String else { continue }
                out.append(VodItem(
                    id: id, name: name,
                    cover: o["stream_icon"] as? String ?? "",
                    year: o["year"] as? String ?? "",
                    rating: (o["rating"] as? String) ?? (o["rating"] as? NSNumber)?.stringValue ?? "",
                    plot: o["plot"] as? String ?? "",
                    ext: o["container_extension"] as? String ?? "mp4",
                    catId: (o["category_id"] as? String) ?? "",
                    type: "m",
                    addedMs: parseEpoch(o["added"])))
            }
        }
        return out
    }

    static func fetchSeriesCategories(account: XtreamAccount, password: String) async throws -> [String: String] {
        let b = base(server: account.server, user: account.username, pass: password)
        let json = try await getJSON(b + "&action=get_series_categories")
        var cats = [String: String]()
        if let arr = json as? [[String: Any]] {
            for o in arr {
                if let id = o["category_id"] as? String, let name = o["category_name"] as? String { cats[id] = name }
            }
        }
        return cats
    }

    static func fetchSeries(account: XtreamAccount, password: String, categoryId: String? = nil) async throws -> [VodItem] {
        let b = base(server: account.server, user: account.username, pass: password)
        var url = b + "&action=get_series"
        if let cat = categoryId { url += "&category_id=\(cat)" }
        let json = try await getJSON(url)
        var out = [VodItem]()
        if let arr = json as? [[String: Any]] {
            for o in arr {
                guard let id = (o["series_id"] as? String) ?? (o["series_id"] as? NSNumber)?.stringValue,
                      let name = o["name"] as? String else { continue }
                out.append(VodItem(
                    id: id, name: name,
                    cover: o["cover"] as? String ?? "",
                    year: o["year"] as? String ?? "",
                    rating: (o["rating"] as? String) ?? (o["rating"] as? NSNumber)?.stringValue ?? "",
                    plot: o["plot"] as? String ?? "",
                    ext: "mp4",
                    catId: (o["category_id"] as? String) ?? "",
                    type: "s",
                    addedMs: parseEpoch(o["last_modified"])))
            }
        }
        return out
    }

    /// Full series detail: seasons -> episodes (Android get_series_info).
    static func fetchSeriesInfo(account: XtreamAccount, password: String, seriesId: String) async throws -> SeriesInfo {
        let b = base(server: account.server, user: account.username, pass: password)
        let json = try await getJSON(b + "&action=get_series_info&series_id=\(seriesId)")
        var info = SeriesInfo()
        guard let root = json as? [String: Any] else { return info }
        if let md = root["info"] as? [String: Any] {
            info.cover = md["cover"] as? String ?? ""
            info.plot = md["plot"] as? String ?? ""
            info.rating = (md["rating"] as? String) ?? (md["rating"] as? NSNumber)?.stringValue ?? ""
            info.year = md["year"] as? String ?? ""
        }
        if let eps = root["episodes"] as? [String: [[String: Any]]] {
            for (season, list) in eps {
                var episodes = [Episode]()
                for o in list {
                    guard let id = (o["id"] as? String) ?? (o["id"] as? NSNumber)?.stringValue else { continue }
                    episodes.append(Episode(
                        id: id,
                        title: o["title"] as? String ?? "",
                        season: season,
                        ext: o["container_extension"] as? String ?? "mp4",
                        addedMs: parseEpoch(o["added"]),
                        epNum: o["episode_num"] as? Int ?? 0))
                }
                episodes.sort { $0.epNum < $1.epNum }
                info.seasons[season] = episodes
            }
        }
        return info
    }

    /// Movie detail (Android get_vod_info).
    static func fetchVodInfo(account: XtreamAccount, password: String, vodId: String) async throws -> [String: String] {
        let b = base(server: account.server, user: account.username, pass: password)
        let json = try await getJSON(b + "&action=get_vod_info&vod_id=\(vodId)")
        var out = [String: String]()
        if let root = json as? [String: Any], let md = root["movie_data"] as? [String: Any] {
            for (k, v) in md { out[k] = "\(v)" }
        }
        return out
    }

    // MARK: - Stream URLs

    static func liveURL(account: XtreamAccount, password: String, streamId: String) -> String {
        "\(account.server)/live/\(account.username)/\(password)/\(streamId).ts"
    }

    static func vodURL(_ item: VodItem, account: XtreamAccount?, password: String?) -> String {
        let srv = item.accServer ?? account?.server ?? ""
        let u = item.accUser ?? account?.username ?? ""
        let pw = item.accPass ?? password ?? ""
        let ext = item.ext.isEmpty ? "mp4" : item.ext
        return "\(srv)/movie/\(u)/\(pw)/\(item.id).\(ext)"
    }

    static func episodeURL(_ ep: Episode, account: XtreamAccount?, password: String?) -> String {
        let srv = ep.accServer ?? account?.server ?? ""
        let u = ep.accUser ?? account?.username ?? ""
        let pw = ep.accPass ?? password ?? ""
        let ext = ep.ext.isEmpty ? "mp4" : ep.ext
        return "\(srv)/series/\(u)/\(pw)/\(ep.id).\(ext)"
    }

    // MARK: - M3U

    /// Parses an M3U playlist the Android way: #EXTINF tvg-name/tvg-logo/
    /// group-title, then the URL on the next non-# line.
    static func fetchM3U(urlString: String) async throws -> ([String: String], [Channel]) {
        let data = try await get(urlString, timeout: 30)
        guard let body = String(data: data, encoding: .utf8) else { throw XtreamError.badResponse }
        var cats = [String: String]()
        var out = [Channel]()
        var pendingName: String?
        var pendingLogo: String?
        var pendingGroup: String?
        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                pendingLogo = attr(line, "tvg-logo")
                pendingGroup = attr(line, "group-title")
                let nm = attr(line, "tvg-name")
                let after = line.split(separator: ",", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                pendingName = !nm.isEmpty ? nm : after
            } else if !line.isEmpty && !line.hasPrefix("#"), let name = pendingName {
                let g = (pendingGroup == nil || pendingGroup!.isEmpty) ? L("أخرى", "Other") : pendingGroup!
                if !cats.values.contains(g) { cats[g] = g }
                var ch = Channel(id: "mu:\(line)", name: name, url: line, catId: g, categoryName: g, logo: pendingLogo ?? "")
                computeFlags(&ch)
                out.append(ch)
                pendingName = nil; pendingLogo = nil; pendingGroup = nil
            }
        }
        if out.isEmpty { throw XtreamError.emptyPlaylist }
        return (cats, out)
    }

    private static func attr(_ line: String, _ key: String) -> String {
        let k = key + "=\""
        guard let i = line.range(of: k) else { return "" }
        let rest = line[i.upperBound...]
        guard let j = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<j])
    }

    // MARK: - Helpers

    /// Flags computed once at load (Android computeFlags()).
    static func computeFlags(_ ch: inout Channel) {
        ch.isEgyptian = isEgyptian(name: ch.name)
        ch.isCartoon = isCartoonName(ch.name, ch.categoryName)
        ch.isNilesat = isNilesat(name: ch.name)
        ch.smart = smartFold(ch.name)
        ch.smartToks = smartTokens(ch.smart)
    }

    /// Xtream "added"/"last_modified" come as epoch seconds (string or number).
    private static func parseEpoch(_ v: Any?) -> TimeInterval {
        if let s = v as? String, let d = Double(s) { return d > 1e12 ? d / 1000 : d }
        if let n = v as? NSNumber { let d = n.doubleValue; return d > 1e12 ? d / 1000 : d }
        return 0
    }
}
