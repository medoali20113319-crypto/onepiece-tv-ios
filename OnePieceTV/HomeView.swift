// HomeView.swift — live TV: category chips with counts, channel grid
// with logos, smart search + live suggestions, the Nilesat bundle and
// the private list («قايمتي»). Tapping a channel opens fullscreen at
// once (Android v4.18 rule); long-press gives favorite / rename / hide /
// move. Search inside Nilesat filters the bundle only (Android v4.19).

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedCategory: String? = nil   // nil = all
    @State private var showNilesat = false
    @State private var showFavorites = false
    @State private var query = ""
    @State private var playing: Channel?
    @State private var playingContext: [Channel] = []
    @State private var renameTarget: Channel?
    @State private var renameText = ""
    @State private var moveTarget: Channel?
    @State private var moveText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                categoryChips
                if !query.isEmpty {
                    suggestionsList
                } else {
                    channelGrid
                }
            }
            .navigationTitle("One Piece TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { LibraryView() } label: {
                        Image(systemName: "film")
                    }
                }
            }
            .refreshable { await store.loadLive() }
            .fullScreenCover(item: $playing) { ch in
                PlayerView(channel: ch, context: playingContext, isPresented: Binding(
                    get: { playing != nil },
                    set: { if !$0 { playing = nil } }))
            }
            .alert(L("تغيير الاسم", "Rename"), isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })) {
                    TextField(L("الاسم الجديد", "New name"), text: $renameText)
                    Button(L("حفظ", "Save")) {
                        if let t = renameTarget { store.rename(t, to: renameText) }
                    }
                    Button(L("إلغاء", "Cancel"), role: .cancel) {}
                }
            .alert(L("انقل للقناة رقم…", "Move to position…"), isPresented: Binding(
                get: { moveTarget != nil },
                set: { if !$0 { moveTarget = nil } })) {
                    TextField("1", text: $moveText).keyboardType(.numberPad)
                    Button(L("نقل", "Move")) {
                        if let t = moveTarget, let pos = Int(moveText) {
                            store.moveChannel(t, in: listKey, to: pos)
                        }
                    }
                    Button(L("إلغاء", "Cancel"), role: .cancel) {}
                }
        }
        .task { if store.channels.isEmpty { await store.loadLive() } }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField(L("دوّر على قناة…", "Search channels…"), text: $query)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var suggestionsList: some View {
        List(store.suggestions(for: query, in: currentList), id: \.id) { ch in
            Button { openPlayer(ch) } label: {
                HStack {
                    ChannelLogo(url: ch.logo)
                    Text(ch.displayName).lineLimit(1)
                    Spacer()
                    Text(ch.categoryName).font(.caption).opacity(0.6)
                }
            }
            .contextMenu { channelMenu(ch) }
        }
        .listStyle(.plain)
    }

    // MARK: - Categories

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                specialChip(title: "⭐ " + L("قايمتي", "My list"), active: showFavorites, count: store.favoriteChannels.count) {
                    showFavorites.toggle(); showNilesat = false; selectedCategory = nil
                }
                specialChip(title: "🛰️ " + L("باقة النايل سات", "Nilesat bundle"), active: showNilesat, count: store.nilesatChannels.count) {
                    showNilesat.toggle(); showFavorites = false; selectedCategory = nil
                }
                ForEach(sortedCategories, id: \.0) { id, name in
                    let count = store.channels.filter { $0.catId == id }.count
                    Button("\(name) (\(count))") {
                        selectedCategory = id; showNilesat = false; showFavorites = false
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedCategory == id ? .yellow : .gray)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func specialChip(title: String, active: Bool, count: Int, action: @escaping () -> Void) -> some View {
        Button("\(title) (\(count))", action: action)
            .buttonStyle(.bordered)
            .tint(active ? .yellow : .gray)
    }

    private var sortedCategories: [(String, String)] {
        store.categories.sorted { $0.value < $1.value }
    }

    // MARK: - Grid

    private var currentList: [Channel] {
        if showFavorites { return store.favoriteChannels }
        if showNilesat { return store.nilesatChannels }
        if let cat = selectedCategory { return store.channels(forCategory: cat) }
        return store.channels
    }

    private var listKey: String {
        if showNilesat { return "NILE" }
        return selectedCategory ?? "ALL"
    }

    private var channelGrid: some View {
        Group {
            if store.isLoading && store.channels.isEmpty {
                ProgressView(L("جاري تحميل القنوات…", "Loading channels…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.loadError, store.channels.isEmpty {
                VStack(spacing: 12) {
                    Text(err).foregroundColor(.red)
                    Button(L("حاول تاني", "Retry")) { Task { await store.loadLive() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if currentList.isEmpty {
                Text(L("مفيش قنوات هنا", "No channels here"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(currentList) { ch in
                            ChannelCell(channel: ch)
                                .onTapGesture { openPlayer(ch) }
                                .contextMenu { channelMenu(ch) }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Channel menu (long-press)

    @ViewBuilder
    private func channelMenu(_ ch: Channel) -> some View {
        Button(store.favorites.contains(ch.id) ? L("❌ شيل من قايمتي", "❌ Remove from my list") : L("⭐ ضيف لقايمتي", "⭐ Add to my list")) {
            store.toggleFavorite(ch)
        }
        Button(L("✏️ تغيير الاسم", "✏️ Rename")) {
            renameTarget = ch
            renameText = ch.displayName
        }
        if listKey != "ALL" {
            Button(L("⬆️ انقل فوق", "⬆️ Move up")) {
                store.moveChannel(ch, in: listKey, direction: -1)
            }
            Button(L("⬇️ انقل تحت", "⬇️ Move down")) {
                store.moveChannel(ch, in: listKey, direction: 1)
            }
            Button(L("🔢 انقل لرقم…", "🔢 Move to number…")) {
                moveTarget = ch
                moveText = ""
            }
            Button(L("↩️ إرجاع الترتيب الأصلي", "↩️ Reset to original order")) {
                store.resetOrder(key: listKey)
            }
        }
        Button(L("🙈 إخفاء القناة", "🙈 Hide channel"), role: .destructive) {
            store.hide(ch)
        }
    }

    private func openPlayer(_ ch: Channel) {
        playingContext = currentList
        playing = ch
    }
}

// MARK: - Cells

struct ChannelLogo: View {
    let url: String
    var body: some View {
        if let u = URL(string: url), !url.isEmpty {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                default: Image(systemName: "tv").foregroundColor(.gray)
                }
            }
            .frame(width: 44, height: 44)
        } else {
            Image(systemName: "tv").frame(width: 44, height: 44).foregroundColor(.gray)
        }
    }
}

struct ChannelCell: View {
    let channel: Channel
    var body: some View {
        VStack(spacing: 6) {
            ChannelLogo(url: channel.logo)
                .frame(height: 48)
            Text(channel.displayName)
                .font(.caption).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
