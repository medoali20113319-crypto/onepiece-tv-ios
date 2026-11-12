// PlayerView.swift — fullscreen AVPlayer with channel zap, EPG strip,
// dubbing toggle and the Android .ts -> .m3u8 retry.

import SwiftUI
import AVKit
import AVFoundation

struct PlayerView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dubbing = DubbingEngine()

    let channel: Channel
    /// The list the channel was opened from — drives the zap queue
    /// (Android v4.19 playCtx).
    let context: [Channel]
    @Binding var isPresented: Bool

    @State private var player = AVPlayer()
    @State private var current: Channel
    @State private var epg: [EpgEntry] = []
    @State private var showBars = true
    @State private var errorText: String?
    @State private var triedM3U8 = false
    @State private var hideTask: Task<Void, Never>?

    init(channel: Channel, context: [Channel], isPresented: Binding<Bool>) {
        self.channel = channel
        self.context = context
        self._isPresented = isPresented
        self._current = State(initialValue: channel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onTapGesture { toggleBars() }
            if showBars {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
            if let errorText = errorText {
                VStack {
                    Text(errorText).foregroundColor(.white).padding()
                        .background(Color.black.opacity(0.7)).cornerRadius(10)
                }
            }
        }
        .onAppear { play(current) }
        .onDisappear {
            dubbing.stop()
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)) { _ in
            retryWithM3U8IfNeeded()
        }
        .statusBar(hidden: true)
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            Button(action: { isPresented = false }) {
                Image(systemName: "chevron.backward").font(.title2)
            }
            Text(current.displayName).font(.headline).lineLimit(1)
            Spacer()
            Button(action: toggleDubbing) {
                Label(dubbing.isActive ? L("🎙️ دبلجة شغالة", "🎙️ Dubbing on") : L("🎙️ دبلجة", "🎙️ Dubbing"),
                      systemImage: dubbing.isActive ? "mic.fill" : "mic")
            }
            .buttonStyle(.bordered)
            .tint(dubbing.isActive ? .yellow : .white)
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.opacity(0.5))
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if !epg.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(epg) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).font(.caption).bold()
                                Text("\(e.start) - \(e.end)").font(.caption2).opacity(0.8)
                            }
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            HStack {
                Button(action: { zap(-1) }) {
                    Image(systemName: "chevron.left").font(.title)
                }
                Spacer()
                Button(action: togglePlayPause) {
                    Image(systemName: player.timeControlStatus == .playing ? "pause.fill" : "play.fill").font(.title)
                }
                Spacer()
                Button(action: { zap(1) }) {
                    Image(systemName: "chevron.right").font(.title)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            if !dubbing.lastSpokenArabic.isEmpty {
                Text(dubbing.lastSpokenArabic).font(.caption).foregroundColor(.yellow)
                    .lineLimit(2).padding(.horizontal)
            }
        }
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Playback

    private func play(_ ch: Channel) {
        errorText = nil
        triedM3U8 = false
        current = ch
        guard let url = URL(string: ch.url) else {
            errorText = L("رابط القناة مش صحيح", "Bad channel URL")
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        scheduleHideBars()
        loadEPG(for: ch)
        if dubbing.isActive {
            Task { _ = await dubbing.start(player: player, item: item) }
        }
    }

    /// Retry once with the .m3u8 variant before giving up (Android v4.x).
    private func retryWithM3U8IfNeeded() {
        guard !triedM3U8, current.url.hasSuffix(".ts") else {
            errorText = L("القناة مش شغالة دلوقتي", "Channel is not playing right now")
            return
        }
        triedM3U8 = true
        let alt = String(current.url.dropLast(3)) + ".m3u8"
        if let url = URL(string: alt) {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
    }

    private func zap(_ direction: Int) {
        guard let idx = context.firstIndex(of: current) else { return }
        let next = idx + direction
        guard next >= 0 && next < context.count else { return }
        play(context[next])
    }

    private func togglePlayPause() {
        if player.timeControlStatus == .playing { player.pause() }
        else { player.play() }
    }

    private func toggleBars() {
        withAnimation { showBars.toggle() }
        if showBars { scheduleHideBars() }
    }

    private func scheduleHideBars() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)  // Android: auto-hide after 10s
            await MainActor.run { withAnimation { showBars = false } }
        }
    }

    private func toggleDubbing() {
        if dubbing.isActive {
            dubbing.stop()
        } else {
            guard let item = player.currentItem else { return }
            Task {
                let ok = await dubbing.start(player: player, item: item)
                if !ok { errorText = dubbing.statusMessage }
            }
        }
    }

    private func loadEPG(for ch: Channel) {
        guard let account = store.currentAccount, account.isXtream,
              ch.id.hasPrefix("xt:") else { return }
        let sid = String(ch.id.dropFirst(3))
        let pw = store.password(for: account) ?? ""
        Task {
            do {
                let entries = try await XtreamAPI.fetchShortEPG(account: account, password: pw, streamId: sid)
                await MainActor.run { epg = entries }
            } catch { /* EPG is best-effort; silence the failure */ }
        }
    }
}
