// Search.swift — port of the Android v4.19 smart search (MainActivity.java).
// Both the query and every channel name are normalized once to a canonical
// form: foldAr + an AR/EN common-words map, so «بين» finds beIN and
// «bein» finds «بين سبورت». Channel forms are computed once when channels
// load, never per keystroke.

import Foundation

/// Arabic folding: أ/إ/آ → ا, ة → ه, ى → ي, tatweel → space, collapse spaces.
func foldAr(_ s: String?) -> String {
    guard let s = s else { return "" }
    var out = s.lowercased()
    out = out.replacingOccurrences(of: "أ", with: "ا")
        .replacingOccurrences(of: "إ", with: "ا")
        .replacingOccurrences(of: "آ", with: "ا")
        .replacingOccurrences(of: "ة", with: "ه")
        .replacingOccurrences(of: "ى", with: "ي")
        .replacingOccurrences(of: "ـ", with: " ")
    // collapse whitespace
    out = out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    return out.trimmingCharacters(in: .whitespaces)
}

/// Word tokens of a string (letters/digits only, folded).
func tokensOf(_ s: String?) -> Set<String> {
    var t = Set<String>()
    for w in foldAr(s).components(separatedBy: CharacterSet.alphanumerics.inverted) {
        if !w.isEmpty { t.insert(w) }
    }
    return t
}

/// Ordered tokens (order matters for "first word" rules like "ON").
func tokensList(_ s: String?) -> [String] {
    foldAr(s).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
}

func hasArabic(_ s: String?) -> Bool {
    guard let s = s else { return false }
    return s.unicodeScalars.contains { $0.value >= 0x0600 && $0.value <= 0x06FF }
}

func hasAny(_ t: Set<String>, _ keys: Set<String>) -> Bool {
    !t.isDisjoint(with: keys)
}

// MARK: - Smart words map (Arabic and English spellings -> one key)

private let smartWords: [String: String] = {
    var m = [String: String]()
    func put(_ canonical: String, _ variants: String...) {
        for v in variants { m[v] = canonical }
    }
    put("bein", "bein", "بين", "بيين", "بي ان")
    put("sport", "sport", "sports", "سبورت", "سبورتس", "رياضه", "رياضة")
    put("movie", "movie", "movies", "افلام", "أفلام", "فيلم")
    put("news", "news", "اخبار", "أخبار")
    put("drama", "drama", "دراما")
    put("cinema", "cinema", "سينما")
    put("kids", "kids", "kid", "اطفال", "أطفال")
    put("music", "music", "موسيقى", "موسيقا", "موسيقي")
    put("series", "series", "مسلسلات", "مسلسل")
    put("doc", "documentary", "documentaries", "وثائقي", "وثائقى")
    put("comedy", "comedy", "كوميدي", "كوميديا")
    put("action", "action", "اكشن", "أكشن")
    put("horror", "horror", "رعب")
    put("romance", "romance", "رومانسي", "رومانسى")
    put("cartoon", "cartoon", "كارتون", "كرتون")
    put("channel", "channel", "channels", "قناه", "قناة", "قنوات")
    put("live", "live", "مباشر")
    put("premium", "premium", "بريميوم")
    put("plus", "plus", "بلس")
    put("egypt", "egypt", "masr", "مصر", "مصري", "مصرية", "المصريه", "المصرية")
    put("arab", "arab", "arabic", "عربي", "عربيه", "العربية", "العربيه")
    put("jazeera", "jazeera", "aljazeera", "الجزيره", "الجزيرة")
    put("natgeo", "natgeo", "national", "geographic", "ناشيونال", "جيوجرافيك")
    put("discovery", "discovery", "ديسكفري")
    put("history", "history", "هيستوري")
    put("food", "food", "طبخ", "مطبخ")
    put("fashion", "fashion", "ازياء", "أزياء")
    put("quran", "quran", "قران", "قرآن")
    put("religion", "religion", "ديني", "دينى", "اسلامي", "إسلامي")
    return m
}()

/// Canonical search form: foldAr, then map every token through the
/// common-words map. "beIN Sports HD 1" and "بين سبورت" both fold to
/// "bein sport hd 1".
func smartFold(_ s: String?) -> String {
    guard let s = s else { return "" }
    var f = foldAr(s)
    f = f.replacingOccurrences(of: "اتش دي", with: "hd")
    var out = [String]()
    for w in f.components(separatedBy: CharacterSet.alphanumerics.inverted) {
        if w.isEmpty { continue }
        out.append(smartWords[w] ?? w)
    }
    return out.joined(separator: " ")
}

func smartTokens(_ smart: String?) -> [String] {
    guard let smart = smart else { return [] }
    return smart.split(separator: " ").map(String.init).filter { !$0.isEmpty }
}

// MARK: - Fuzzy matching

/// Levenshtein distance with an early abort: returns a value > max as soon
/// as it is proven the distance exceeds max.
func lev(_ a: String?, _ b: String?, _ max: Int) -> Int {
    let a = Array(a ?? ""), b = Array(b ?? "")
    let n = a.count, m = b.count
    if abs(n - m) > max { return max + 1 }
    if n == 0 { return m }
    if m == 0 { return n }
    var prev = Array(0...m)
    var cur = Array(repeating: 0, count: m + 1)
    for i in 1...n {
        cur[0] = i
        var rowMin = cur[0]
        for j in 1...m {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            let v = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
            cur[j] = v
            if v < rowMin { rowMin = v }
        }
        if rowMin > max { return max + 1 }
        swap(&prev, &cur)
    }
    return prev[m]
}

/// Is the query token a subsequence of the name token (letters in order,
/// some missing)? Catches dropped letters, e.g. "bein" in "beinsport".
func isSubseq(_ sub: String, _ full: String) -> Bool {
    if sub.isEmpty { return true }
    let subChars = Array(sub), fullChars = Array(full)
    var j = 0
    for i in 0..<fullChars.count where j < subChars.count {
        if fullChars[i] == subChars[j] { j += 1 }
    }
    return j == subChars.count
}

/// Smart match of one query token against one name token: exact, prefix,
/// subsequence, or 1-2 typos (Levenshtein). Short tokens (<= 2 letters)
/// only match exactly.
func tokenMatches(_ qt: String, _ nt: String) -> Bool {
    if qt == nt { return true }
    if qt.count <= 2 || nt.count <= 2 { return false }
    if nt.hasPrefix(qt) || qt.hasPrefix(nt) { return true }
    if isSubseq(qt, nt) { return true }
    let allowed = min(qt.count, nt.count) <= 4 ? 1 : 2
    return lev(qt, nt, allowed) <= allowed
}

/// Score a channel name against a query: 2 = substring match on the
/// canonical form (exact, incl. AR<->EN), 1 = every query token matches
/// some name token (fuzzy), 0 = no match.
func smartMatchScore(nameSmart: String?, nameToks: [String], qSmart: String?, qToks: [String]) -> Int {
    guard let qSmart = qSmart, !qSmart.isEmpty else { return 0 }
    if let nameSmart = nameSmart, nameSmart.contains(qSmart) { return 2 }
    if qToks.isEmpty { return 0 }
    for qt in qToks {
        if qt.count < 3 {
            if nameSmart == nil || !nameSmart!.contains(qt) { return 0 }
            continue
        }
        var ok = false
        for nt in nameToks where tokenMatches(qt, nt) { ok = true; break }
        if !ok { return 0 }
    }
    return 1
}

/// Smart match for a plain label (category names): canonical substring
/// first, then the token-wise fuzzy test.
func smartTextMatch(_ text: String?, qSmart: String?, qToks: [String]) -> Int {
    guard let qSmart = qSmart, !qSmart.isEmpty else { return 0 }
    let s = smartFold(text)
    return smartMatchScore(nameSmart: s, nameToks: smartTokens(s), qSmart: qSmart, qToks: qToks)
}
