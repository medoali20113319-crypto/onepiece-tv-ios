// Nilesat.swift — port of the Android v4.14/v4.17/v4.20 bundle logic
// (MainActivity.java). Layered veto-first matching, name only — no
// provider-category rule. A bare foreign name with no marker is out by
// default: no accept rule = not in the bundle.

import Foundation

// MARK: - Shared sets

private let nileCompanions: Set<String> = ["tv", "sports", "drama", "cinema", "comedy", "life", "family", "news", "international"]
private let cbcCompanions: Set<String> = ["drama", "extra", "sofra", "two"]
private let tenAllowed: Set<String> = ["ten", "tv", "hd", "sd", "live", "channel", "تن"]
private let nileCompounds: Set<String> = ["nilesports", "niledrama", "nilecinema", "nilecomedy", "nilelife", "nilefamily", "nilenews"]

private let egyVeto: Set<String> = [
    "fr", "france", "fra", "usa", "us", "america", "uk", "england",
    "alb", "albania", "br", "brazil", "bra", "ita", "italy", "is", "israel",
    "alg", "algeria", "morocco", "المغرب", "tunisia", "tunisie", "libya",
    "saudi", "السعوديه", "saudiarabia", "uae", "الامارات", "emirates",
    "qatar", "kuwait", "bahrain", "oman", "yemen", "jordan", "lebanon",
    "syria", "iraq", "iran", "turkey", "turkiye", "palestine", "sudan",
    "christ", "christian", "de", "ger", "germany", "esp", "spain",
    "por", "portugal", "ned", "netherlands", "belgium", "switzerland",
    "austria", "greece", "russia", "ukraine", "poland", "romania",
    "serbia", "croatia", "india", "pakistan", "china", "japan", "korea",
    "canada", "mexico", "argentina", "chile", "colombia", "peru", "australia"]

private let egyExplicit: Set<String> = ["مصر", "egypt", "masr", "cairo", "القاهره", "النيل"]

// The Egyptian ON family: every token in this set ("ON TV", "ON Drama",
// "ON E", "ON Time Sports", "ON Sport").
private let onAllowed: Set<String> = ["on", "tv", "drama", "e", "time", "sports", "sport", "hd", "sd", "live", "channel"]

private let nileVeto: Set<String> = [
    "fr", "fra", "france", "french", "france24",
    "uk", "england", "english", "britain", "british", "bbc",
    "usa", "us", "america", "american", "canada", "canadian",
    "de", "ger", "germany", "german", "deutsche", "dw",
    "ita", "italy", "italian", "italia",
    "esp", "spain", "spanish", "por", "portugal", "portuguese",
    "ned", "netherlands", "dutch", "belgium", "belgian",
    "switzerland", "swiss", "austria", "austrian",
    "sweden", "swedish", "swe", "norway", "norwegian", "nor", "dk",
    "denmark", "danish", "finland", "finnish",
    "poland", "polish", "pol", "russia", "russian", "ru", "rus",
    "ukraine", "ukrainian", "ua", "ukr",
    "greece", "greek", "gr", "gre", "romania", "romanian", "ro", "rou",
    "serbia", "serbian", "rs", "srb", "croatia", "croatian", "hr",
    "bosnia", "bosnian", "ba", "balkans",
    "alb", "albania", "albanian", "alg", "algeria", "algerian",
    "turkey", "turkiye", "turkish", "tr", "tur", "trt",
    "iran", "iranian", "ir", "irn", "persian", "farsi",
    "india", "indian", "ind", "hindi", "pakistan", "pakistani", "pk",
    "urdu", "bangladesh", "bengali", "bd", "afghanistan", "afghan", "af",
    "china", "chinese", "cn", "chn", "japan", "japanese", "jp", "jpn",
    "korea", "korean", "kr", "kor",
    "thailand", "thai", "th", "tha", "vietnam", "vietnamese", "vn",
    "philippines", "filipino", "ph", "indonesia", "indonesian",
    "malaysia", "malay", "australia", "australian",
    "mexico", "mexican", "mx", "brazil", "brazilian", "br", "bra",
    "argentina", "argentinian", "arg", "chile", "colombia", "peru",
    "israel", "israeli", "is", "hebrew",
    "armenia", "armenian", "azerbaijan", "azerbaijani", "az",
    "georgia", "georgian", "kazakhstan", "kz", "uzbekistan", "uz",
    "kurdish", "kurdistan",
    "cnn", "euronews", "rt",
    "one", "hurra", "hotbird", "astra", "eutelsat",
    "christ", "christian", "czech", "cz", "cze", "hungary", "hungarian", "hu",
    "bulgaria", "bulgarian", "bg", "tamil", "telugu", "punjabi",
    "espanol", "español", "cgtn", "angel", "alalam", "alam",
    "i24news", "i24", "ifilm", "kairali", "brasil", "turk",
    "god", "loveworld", "llbn", "sender", "neu", "zagros",
    "gyeongnam", "gyeonggi", "gangwon", "daejeon", "daegu", "busan", "seoul",
    "kbs", "sbs", "jtbc", "tvn",
    "viet", "vietnam", "vietnamese", "vie", "phim", "giai", "bibi", "o2tv"]

private let nileExplicit: Set<String> = [
    "مصر", "egypt", "egyptian", "masr", "القاهره", "cairo",
    "السعوديه", "saudi", "saudia", "saudiya",
    "الامارات", "emirates", "emirati",
    "قطر", "qatar", "qatari", "الكويت", "kuwait", "kuwaiti",
    "البحرين", "bahrain", "bahraini", "عمان", "oman", "omani",
    "الاردن", "jordan", "jordanian", "لبنان", "lebanon", "lebanese",
    "سوريا", "syria", "syrian", "العراق", "iraq", "iraqi",
    "iraqiya", "iraqia", "اليمن", "yemen", "yemeni",
    "فلسطين", "palestine", "palestinian",
    "المغرب", "morocco", "moroccan", "الجزائر", "algeria", "algerian",
    "تونس", "tunisia", "tunisian", "ليبيا", "libya", "libyan",
    "السودان", "sudan", "sudanese", "موريتانيا", "mauritania",
    "الصومال", "somalia", "جيبوتي", "djibouti",
    "عربي", "العربيه", "arab", "arabic", "arabia", "arabiya",
    "الخليج", "gulf", "khaliji", "khalijiah", "maghreb", "maghribia",
    "nilesat", "arabsat", "النيل"]

private let toonContains = ["كرتون", "كارتون", "cartoon", "spacetoon",
    "سبيستون", "كراميش", "طيور", "براعم", "ماجد", "ديزني", "disney",
    "nickelodeon", "boomerang", "mbc3", "ducktv", "babytv", "moonbug"]
private let toonTokens: Set<String> = ["cartoon", "cartoons", "cn", "boomerang",
    "spacetoon", "mbc3", "karameesh", "toyor", "baraem", "jeem", "majid", "nick",
    "nickelodeon", "disney", "disneyjunior", "disneyxd", "babytv", "ducktv", "moonbug",
    "kids", "kid", "kido", "junior", "cartoonito", "cbeebies", "كرتون", "كارتون",
    "سبيستون", "كراميش", "طيور", "براعم", "ماجد", "جيم", "ديزني", "اطفال"]
private let toonCats = ["cartoon", "kids", "اطفال", "كرتون", "كارتون", "children", "animation"]

// MARK: - Egyptian (v4.14)

func isEgyptian(name: String) -> Bool {
    let tl = tokensList(name)
    let t = Set(tl)
    for w in t where egyVeto.contains(w) { return false }
    for k in egyExplicit where t.contains(k) { return true }
    if t.contains("nile") {
        for k in nileCompanions where t.contains(k) { return true }
    }
    let first = tl.first ?? ""
    if first == "on" { return true }
    if t.contains("ontv") || t.contains("ondrama") || t.contains("ontime") || t.contains("ontimesports") { return true }
    if t.contains("cbcdrama") { return true }
    if t.contains("cbc") && (hasArabic(name) || hasAny(t, cbcCompanions)) { return true }
    if t.contains("dmc") || t.contains("dmcdrama") { return true }
    if t.contains("mbcmasr") { return true }
    if t.contains("mbc") && (t.contains("masr") || t.contains("مصر") || t.contains("egypt")) { return true }
    if t.contains("nahar") || t.contains("alnahar") || t.contains("النهار") { return true }
    if t.contains("hayat") || t.contains("alhayat") || t.contains("الحياه") { return true }
    if t.contains("sadabalad") { return true }
    if t.contains("sada") && t.contains("balad") { return true }
    if t.contains("صدي") && t.contains("البلد") { return true }
    if t.contains("kahera") || t.contains("alkahera") { return true }
    if t.contains("alnas") { return true }
    if t.contains("الناس") && t.contains("القاهره") { return true }
    if t.contains("mehwar") || t.contains("almehwar") || t.contains("المحور") { return true }
    if t.contains("ten") && t.contains("تن") {
        if t.allSatisfy({ tenAllowed.contains($0) }) { return true }
    }
    if t.contains("dream") || t.contains("دريم") { return true }
    for k in nileCompounds where t.contains(k) { return true }
    if (t.contains("الاولي") || t.contains("الثانيه")) && (t.contains("المصريه") || t.contains("القناه")) { return true }
    return false
}

// MARK: - Nilesat bundle (v4.17)

func isNilesat(name: String) -> Bool {
    let tl = tokensList(name)
    let t = Set(tl)
    for w in t where nileVeto.contains(w) { return false }
    if t.contains("sat") && t.contains("7") { return false }
    if hasArabic(name) { return true }
    for k in nileExplicit where t.contains(k) { return true }
    for w in t where w.hasPrefix("mbc") || w.hasPrefix("bein") || w.hasPrefix("rotana") { return true }
    if t.contains("jazeera") || t.contains("aljazeera") { return true }
    if t.contains("arabiya") || t.contains("alarabiya") || t.contains("alarabia") { return true }
    let first = tl.first ?? ""
    if first == "on" {
        if tl.allSatisfy({ onAllowed.contains($0) }) { return true }
    }
    if t.contains("ontv") || t.contains("ondrama") || t.contains("ontime") || t.contains("ontimesports") { return true }
    if t.contains("cbcdrama") { return true }
    if t.contains("cbc") && hasAny(t, cbcCompanions) { return true }
    if t.contains("dmc") || t.contains("dmcdrama") { return true }
    if t.contains("nahar") || t.contains("alnahar") || t.contains("النهار") { return true }
    if t.contains("hayat") || t.contains("alhayat") || t.contains("hayah") || t.contains("alhayah") || t.contains("الحياه") { return true }
    if t.contains("sadabalad") { return true }
    if t.contains("sada") && t.contains("balad") { return true }
    if t.contains("صدي") && t.contains("البلد") { return true }
    if t.contains("balad") { return true }
    if t.contains("kahera") || t.contains("alkahera") || t.contains("القاهره") || t.contains("cairo") || t.contains("qahera") || t.contains("alqahera") { return true }
    if t.contains("alnas") { return true }
    if t.contains("al") && t.contains("nas") { return true }
    if t.contains("الناس") && t.contains("القاهره") { return true }
    if t.contains("mehwar") || t.contains("almehwar") || t.contains("المحور") { return true }
    if t.contains("ten") && t.contains("تن") {
        if t.allSatisfy({ tenAllowed.contains($0) }) { return true }
    }
    if t.contains("دريم") { return true }
    if first == "dream" { return true }
    for k in nileCompounds where t.contains(k) { return true }
    if t.contains("nile") {
        if t.contains("sat") { return true }
        for k in nileCompanions where t.contains(k) { return true }
    }
    if (t.contains("الاولي") || t.contains("الثانيه")) && (t.contains("المصريه") || t.contains("القناه")) { return true }
    if t.contains("abudhabi") { return true }
    if t.contains("abu") && t.contains("dhabi") { return true }
    if t.contains("dubai") || t.contains("sharjah") || t.contains("ajman") || t.contains("fujairah") || t.contains("quwain") { return true }
    if t.contains("ras") && t.contains("khaimah") { return true }
    let cities: Set<String> = ["doha", "riyadh", "jeddah", "mecca", "medina", "baghdad", "beirut", "amman", "damascus", "sanaa", "aden", "khartoum", "tripoli", "tunis", "rabat", "casablanca", "algiers", "muscat", "manama", "gaza", "ramallah", "jerusalem", "basra", "mosul", "alexandria"]
    if !t.isDisjoint(with: cities) { return true }
    if t.contains("lbc") || t.contains("lbci") { return true }
    if t.contains("jadeed") || t.contains("aljadeed") { return true }
    if t.contains("manar") || t.contains("almanar") { return true }
    if t.contains("mayadeen") || t.contains("almayadeen") { return true }
    if t.contains("mashhad") || t.contains("almashhad") { return true }
    if t.contains("hadath") || t.contains("alhadath") { return true }
    if t.contains("ghad") || t.contains("alghad") { return true }
    if t.contains("aan") || t.contains("alaan") { return true }
    if t.contains("asharq") { return true }
    if t.contains("sharqiya") || t.contains("alsharqiya") { return true }
    if t.contains("sumaria") || t.contains("alsumaria") { return true }
    if t.contains("rasheed") || t.contains("alrasheed") { return true }
    if t.contains("dijlah") { return true }
    if t.contains("art") { return true }
    if t.contains("ssc") || t.contains("ksa") || t.contains("sbc") { return true }
    if t.contains("riyadiya") || t.contains("thmanyah") { return true }
    if t.contains("shahid") { return true }
    if t.contains("watchit") { return true }
    if t.contains("watch") && t.contains("it") { return true }
    if t.contains("osn") { return true }
    if t.contains("alwan") || t.contains("aflam") { return true }
    if t.contains("moga") || t.contains("panorama") { return true }
    if t.contains("safa") || t.contains("alsafa") { return true }
    if t.contains("hekaya") || t.contains("alhekaya") { return true }
    if t.contains("masriya") || t.contains("almasriya") { return true }
    if t.contains("oula") || t.contains("aloula") || t.contains("thanya") { return true }
    if t.contains("ertu") { return true }
    if t.contains("spacetoon") || t.contains("karameesh") || t.contains("toyor") || t.contains("baraem") || t.contains("jeem") || t.contains("majid") { return true }
    if t.contains("kass") || t.contains("alkass") { return true }
    if t.contains("rayyan") || t.contains("alrayyan") { return true }
    if t.contains("aoula") || t.contains("alaoula") { return true }
    if t.contains("2m") || t.contains("medi1") || t.contains("medi1tv") || t.contains("medi") { return true }
    if t.contains("arryadia") { return true }
    if t.contains("snrt") || t.contains("tamazight") { return true }
    if t.contains("maghribia") || t.contains("almaghribia") { return true }
    if t.contains("ad") && t.contains("sports") { return true }
    if (t.contains("mtv") || t.contains("otv") || t.contains("future")) && (t.contains("lebanon") || t.contains("لبنان")) { return true }
    if first == "extra" && t.contains("news") { return true }
    return false
}

// MARK: - Cartoon

func isCartoonName(_ name: String, _ cat: String) -> Bool {
    let t0 = tokensOf(name)
    if t0.contains("mohandis") || t0.contains("المهندس") { return false }
    let fn = foldAr(name)
    let fc = foldAr(cat)
    for k in toonContains where fn.contains(k) { return true }
    for k in toonCats where fc.contains(k) { return true }
    let t = tokensOf(name)
    for k in toonTokens where t.contains(k) { return true }
    return false
}

// MARK: - Nilesat grouped order (v4.20)

enum NileGroup: Int, CaseIterable {
    case cartoon = 0, natgeo = 1, movieAr = 2, seriesAr = 3, movieFor = 4, seriesFor = 5, news = 6, sport = 7, rest = 8
}

private let nileForeignTokens: Set<String> = [
    "foreign", "اجنبي", "اجنبيه", "english", "انجليزي", "انجليزيه",
    "امريكي", "امريكيه", "america", "امريكا",
    "hollywood", "هوليوود", "bollywood", "بوليود", "هندي", "هنديه", "hindi",
    "british", "بريطاني", "بريطانيه", "مترجم", "مترجمه", "french", "فرنسي", "فرنسيه",
    "turkish", "تركي", "تركيه", "korean", "كوري", "كوريه", "chinese", "صيني", "صينيه",
    "spanish", "اسباني", "اسبانيه", "german", "الماني", "المانيه",
    "italian", "ايطالي", "ايطاليه", "russian", "روسي", "روسيه"]

private let nileMovieKeys: Set<String> = ["mbc2", "mbcaction", "mbcbollywood", "mbcmax", "foxmovies", "starmovies", "osnmovies", "beinmovies", "zeeaflam", "zeecinema"]
private let nileSeriesKeys: Set<String> = ["zeealwan", "zeetv", "starplus", "colorstv", "sonytv"]
private let nileForeignKeys: Set<String> = ["mbc2", "mbcaction", "mbcbollywood", "mbcmax", "foxmovies", "starmovies", "osnmovies", "beinmovies", "zeeaflam", "zeecinema", "zeealwan", "zeetv", "starplus", "colorstv", "sonytv", "beinseries", "osnseries", "foxseries"]

/// Tokens with a leading "ال" / "لل" stripped too.
func expandedTokens(_ s: String?) -> Set<String> {
    var out = Set<String>()
    for w in tokensOf(s) {
        out.insert(w)
        if w.hasPrefix("ال") && w.count > 2 { out.insert(String(w.dropFirst(2))) }
        if w.hasPrefix("لل") && w.count > 2 { out.insert(String(w.dropFirst(2))) }
    }
    return out
}

/// Spaceless folded name, for known-name lookup.
func nameKey(_ s: String?) -> String {
    foldAr(s).components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
}

func knownKey(_ key: String, _ keys: Set<String>) -> Bool {
    keys.contains { key.contains($0) }
}

func isForeignName(_ t: Set<String>, _ key: String) -> Bool {
    for k in nileForeignTokens where t.contains(k) { return true }
    return knownKey(key, nileForeignKeys)
}

func knownNews(fn: String, t: Set<String>, tl: [String], key: String) -> Bool {
    if t.contains("cnn") || t.contains("rt") || t.contains("cnbc") || t.contains("yawm") || t.contains("اليوم") { return true }
    if t.contains("hadath") || t.contains("alhadath") || t.contains("ghad") || t.contains("alghad") || t.contains("arabi") || t.contains("alarabi") { return true }
    if !tl.isEmpty {
        if tl[0] == "alarabiya" { return true }
        if tl.count >= 2 && tl[0] == "al" && tl[1] == "arabiya" { return true }
    }
    var alAan = t.contains("aan") || t.contains("alaan") || t.contains("الان")
    if alAan {
        let allowed: Set<String> = ["al", "aan", "alaan", "الان", "tv", "hd", "sd", "fhd", "uhd", "4k", "live", "channel"]
        for w in tl {
            if allowed.contains(w) || w.range(of: #"^\d+p$"#, options: .regularExpression) != nil { continue }
            alAan = false
            break
        }
        if alAan { return true }
    }
    if key.contains("العربيه") || key.contains("العربي") || key.contains("الحدث") || key.contains("الغد") || key.contains("روسيااليوم") || key.contains("france24") || key.contains("فرانس24") || key.contains("المشهد") || key.contains("almashhad") || key.contains("الميادين") || key.contains("mayadeen") || key.contains("medi1") || key.contains("ikhbaria") || key.contains("اخباريه") { return true }
    if key == "alarabiya" || key.hasPrefix("alarabiya") || key == "alarabi" || key.hasPrefix("alarabi") || key == "alhadath" || key.hasPrefix("alhadath") || key == "alghad" || key.hasPrefix("alghad") { return true }
    let doc = fn.contains("وثائقي") || fn.contains("documentary") || fn.contains("earth")
    if !doc && (key.contains("bbc") || key.contains("الجزيره") || key.contains("aljazeera")) { return true }
    return false
}

/// Pure classifier, unit-testable: the group of one channel by its name
/// (and provider category, for the cartoon check only). First match wins.
func nileGroupOf(name: String, cat: String) -> NileGroup {
    if isCartoonName(name, cat) { return .cartoon }
    let fn = foldAr(name)
    let tl = tokensList(name)
    let st = Set(smartTokens(smartFold(name)))
    let t = expandedTokens(name)
    let key = nameKey(name)
    if st.contains("natgeo") || (t.contains("nat") && t.contains("geo")) || fn.contains("ناشيونال") || fn.contains("جيوجرافيك") { return .natgeo }
    let movie = st.contains("movie") || st.contains("cinema") || st.contains("film")
        || t.contains("aflam") || t.contains("افلام") || t.contains("سينما")
        || t.contains("فيلم") || t.contains("cima") || t.contains("سيما")
        || knownKey(key, nileMovieKeys)
    if movie { return isForeignName(t, key) ? .movieFor : .movieAr }
    let series = st.contains("series") || st.contains("drama")
        || t.contains("مسلسلات") || t.contains("مسلسل")
        || knownKey(key, nileSeriesKeys)
    if series { return isForeignName(t, key) ? .seriesFor : .seriesAr }
    if st.contains("news") || t.contains("نيوز") || t.contains("خبر") || t.contains("اخبار") || knownNews(fn: fn, t: t, tl: tl, key: key) { return .news }
    if st.contains("sport") || t.contains("رياضه") || t.contains("رياضيه") || t.contains("رياضي") || t.contains("كوره") || t.contains("kora") || t.contains("دوري") || t.contains("arryadia") || t.contains("riyadiya") || t.contains("الاهلي") || t.contains("الزمالك") || t.contains("ahly") || t.contains("zamalek") || t.contains("bein") || t.contains("ssc") || t.contains("kass") || t.contains("كاس") { return .sport }
    return .rest
}

/// Group a Nilesat list into stable buckets in group order (v4.20).
/// Within a group the server order is kept (stable buckets).
func groupNilesat(_ channels: [Channel]) -> [Channel] {
    var buckets = [NileGroup: [Channel]]()
    for ch in channels { buckets[nileGroupOf(name: ch.name, cat: ch.categoryName), default: []].append(ch) }
    return NileGroup.allCases.flatMap { buckets[$0] ?? [] }
}
