// LibraryView.swift — movies + series library, anime section with
// One Piece pinned first (Android v4.5), filters (الكل / منتهي / مستمر /
// متوقف / قديم / جديد), series detail with seasons and episodes.

import SwiftUI
import AVKit
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject var store: AppStore

    @State private var tab = 0   // 0 movies, 1 series, 2 anime
    @State private var query = ""
    @State private var filter = "ALL"
    @State private var selectedSeries: VodItem?
    @State private var playingURL: String?
    @State private var playingTitle = ""

    private let filters = ["ALL", "DONE", "ONGOING", "STOPPED", "OLD", "NEW"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text(L("🎬 أفلام", "🎬 Movies")).tag(0)
                    Text(L("📺 مسلسلات", "📺 Series")).tag(1)
                    Text(L("🎨 أنمي", "🎨 Anime")).tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                if tab != 0 {
                    filterRow
                }
                searchField
                content
            }
            .navigationTitle(L("المكتبة", "Library"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedSeries) { item in
                SeriesDetailView(item: item)
            }
            .fullScreenCover(isPresented: Binding(
                get: { playingURL != nil },
                set: { if !$0 { playingURL = nil } })) {
                    if let url = playingURL {
                        SimplePlayerView(url: url, title: playingTitle)
                    }
                }
        }
        .task { if store.movies.isEmpty && store.series.isEmpty { await store.loadLibrary() } }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { f in
                    Button(filterLabel(f)) { filter = f }
                        .buttonStyle(.bordered)
                        .tint(filter == f ? .yellow : .gray)
                }
            }
            .padding(.horizontal)
        }
    }

    private func filterLabel(_ f: String) -> String {
        switch f {
        case "ALL": return L("الكل", "All")
        case "DONE": return L("منتهي", "Finished")
        case "ONGOING": return L("مستمر", "Ongoing")
        case "STOPPED": return L("متوقف", "Paused")
        case "OLD": return L("قديم", "Old")
        case "NEW": return L("جديد", "New")
        default: return f
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField(L("دوّر…", "Search…"), text: $query).autocorrectionDisabled()
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") } }
        }
        .padding(8).background(Color(.systemGray6)).cornerRadius(10)
        .padding(.horizontal).padding(.bottom, 8)
    }

    private var content: some View {
        Group {
            if tab == 0 {
                itemsGrid(filteredMovies, isSeries: false)
            } else if tab == 1 {
                itemsGrid(filteredSeries(store.series), isSeries: true)
            } else {
                let anime = store.series.filter { isToonName($0.name) || isToonCategory(store.seriesCategories[$0.catId]) }
                if anime.isEmpty {
                    Text(L("مفيش أنمي في مكتبة المزود ده — جرّب «الكل» أو دوّر بالاسم", "No anime in this provider's library — try “All” or search by name"))
                        .foregroundColor(.secondary).padding()
                } else {
                    itemsGrid(filteredSeries(anime), isSeries: true)
                }
            }
        }
    }

    private var filteredMovies: [VodItem] {
        var list = store.movies
        if !query.isEmpty {
            let q = foldAr(query)
            list = list.filter { foldAr($0.name).contains(q) }
        }
        return list
    }

    private func filteredSeries(_ items: [VodItem]) -> [VodItem] {
        var list = items
        if !query.isEmpty {
            let q = foldAr(query)
            list = list.filter { foldAr($0.name).contains(q) }
        }
        switch filter {
        case "DONE": list = list.filter { store.seriesStatus($0) == .done }
        case "ONGOING": list = list.filter { store.seriesStatus($0) == .ongoing }
        case "STOPPED": list = list.filter { store.seriesStatus($0) == .stopped }
        case "NEW": list = list.filter { year(of: $0) >= 2015 }
        case "OLD": list = list.filter { let y = year(of: $0); return y > 0 && y < 2015 }
        default: break
        }
        // One Piece first in EVERY series view (Android v4.5).
        return store.pinnedSeries(list)
    }

    private func year(of item: VodItem) -> Int {
        Int(item.year.prefix(4)) ?? 0
    }

    private func itemsGrid(_ items: [VodItem], isSeries: Bool) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    VodCell(item: item)
                        .onTapGesture {
                            if isSeries { selectedSeries = item }
                            else {
                                playingTitle = item.name
                                playingURL = XtreamAPI.vodURL(item, account: store.currentAccount, password: store.password(for: store.currentAccount))
                            }
                        }
                }
            }
            .padding()
        }
    }
}

struct VodCell: View {
    let item: VodItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let u = URL(string: item.cover), !item.cover.isEmpty {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.gray
                    }
                }
                .frame(height: 150)
                .clipped()
                .cornerRadius(10)
            } else {
                Color.gray.frame(height: 150).cornerRadius(10)
            }
            Text((item.isOnePiece ? "🏴‍☠️ " : "") + item.name)
                .font(.caption).lineLimit(2)
            if !item.year.isEmpty {
                Text(item.year).font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Series detail

struct SeriesDetailView: View {
    @EnvironmentObject var store: AppStore
    let item: VodItem

    @State private var info: SeriesInfo?
    @State private var playingURL: String?
    @State private var playingTitle = ""
    @State private var statusOverride: SeriesStatus?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let info = info {
                        if !info.cover.isEmpty, let u = URL(string: info.cover) {
                            AsyncImage(url: u) { phase in
                                if case .success(let img) = phase { img.resizable().scaledToFit() }
                            }
                            .frame(maxHeight: 240)
                        }
                        if !info.plot.isEmpty { Text(info.plot).font(.callout) }
                        HStack(spacing: 16) {
                            if !info.year.isEmpty { Text("📅 \(info.year)") }
                            if !info.rating.isEmpty { Text("⭐ \(info.rating)") }
                            Text(statusText).bold()
                        }
                        .font(.caption)
                        ForEach(info.seasons.keys.sorted(), id: \.self) { season in
                            Text(L("الموسم", "Season") + " \(season)").font(.headline)
                            ForEach(info.seasons[season] ?? []) { ep in
                                Button {
                                    playingTitle = "\(item.name) — \(ep.title)"
                                    playingURL = XtreamAPI.episodeURL(ep, account: store.currentAccount, password: store.password(for: store.currentAccount))
                                } label: {
                                    HStack {
                                        Text("E\(ep.epNum) — \(ep.title.isEmpty ? L("حلقة", "Episode") + " \(ep.epNum)" : ep.title)")
                                        Spacer()
                                        Image(systemName: "play.circle")
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else {
                        ProgressView(L("جاري التحميل…", "Loading…"))
                    }
                    // Status override (long-press on Android; menu here).
                    Menu(L("تغيير الحالة", "Change status")) {
                        Button(L("مستمر", "Ongoing")) { setStatus(.ongoing) }
                        Button(L("منتهي", "Finished")) { setStatus(.done) }
                        Button(L("متوقف", "Paused")) { setStatus(.stopped) }
                        Button(L("تلقائي", "Auto")) { setStatus(nil) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .fullScreenCover(isPresented: Binding(
                get: { playingURL != nil },
                set: { if !$0 { playingURL = nil } })) {
                    if let url = playingURL { SimplePlayerView(url: url, title: playingTitle) }
                }
        }
    }

    private var statusText: String {
        switch store.seriesStatus(item) {
        case .done: return L("منتهي", "Finished")
        case .ongoing: return L("مستمر", "Ongoing")
        case .stopped: return L("متوقف", "Paused")
        }
    }

    private func setStatus(_ s: SeriesStatus?) {
        store.setSeriesStatus(item, s)
    }

    private func load() async {
        guard let account = store.currentAccount else { return }
        let pw = store.password(for: account) ?? ""
        do {
            let info = try await XtreamAPI.fetchSeriesInfo(account: account, password: pw, seriesId: item.id)
            await MainActor.run { self.info = info }
        } catch { /* best-effort */ }
    }
}

// MARK: - Simple VOD player (movies / episodes)

struct SimplePlayerView: View {
    let url: String
    let title: String
    @State private var player = AVPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear {
                    if let u = URL(string: url) {
                        player.replaceCurrentItem(with: AVPlayerItem(url: u))
                        player.play()
                    }
                }
                .onDisappear { player.pause() }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.backward").font(.title2)
                    }
                    Text(title).font(.headline).lineLimit(1)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.5))
                Spacer()
            }
        }
    }
}
