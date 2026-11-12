// LoginView.swift — Xtream Codes login + M3U URL + saved accounts +
// the built-in free card (Android id=builtin-free, no login needed).

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: AppStore

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var m3uURL = ""
    @State private var accountName = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var showM3U = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable().scaledToFit().frame(width: 120, height: 120)
                Text("One Piece TV")
                    .font(.largeTitle).bold().foregroundColor(.yellow)

                if !store.accounts.filter({ $0.id != "builtin-free" }).isEmpty {
                    savedAccountsCard
                }
                freeCard
                xtreamCard
                m3uCard
                if let errorText = errorText {
                    Text(errorText).foregroundColor(.red).font(.callout)
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.95))
        .foregroundColor(.white)
    }

    // MARK: - Cards

    private var savedAccountsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("حساباتك", "Your accounts")).font(.headline)
            ForEach(store.accounts.filter { $0.id != "builtin-free" }) { acc in
                HStack {
                    Button(acc.name) { store.selectAccount(acc) }
                    Spacer()
                    Button(role: .destructive) { store.removeAccount(acc) } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .card()
    }

    private var freeCard: some View {
        Button {
            guard let free = store.accounts.first(where: { $0.id == "builtin-free" }) else { return }
            store.selectAccount(free)
        } label: {
            HStack {
                Text("📺").font(.title)
                VStack(alignment: .leading) {
                    Text(L("قنوات مجانية", "Free channels")).bold()
                    Text(L("من غير تسجيل دخول", "No login needed")).font(.caption).opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
        }
        .card()
    }

    private var xtreamCard: some View {
        VStack(spacing: 12) {
            Text(L("دخول باشتراك Xtream", "Sign in with Xtream")).font(.headline)
            TextField(L("السيرفر (مثال: mar10.sbs)", "Server (e.g. mar10.sbs)"), text: $server)
                .textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
            TextField(L("اسم المستخدم", "Username"), text: $username)
                .textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
            SecureField(L("كلمة السر", "Password"), text: $password)
                .textFieldStyle(.roundedBorder)
            TextField(L("اسم للحساب (مثال: سيرفري)", "Name for this account (e.g. My server)"), text: $accountName)
                .textFieldStyle(.roundedBorder)
            Button(action: loginXtream) {
                if isBusy { ProgressView() } else { Text(L("دخول", "Sign in")).bold() }
            }
            .buttonStyle(.borderedProminent).disabled(isBusy)
            Text(L("بياناتك بتتحفظ على موبايلك بس — كلمة السر في Keychain", "Your details stay only on your phone — the password is in the Keychain"))
                .font(.caption).opacity(0.7)
        }
        .card()
    }

    private var m3uCard: some View {
        VStack(spacing: 12) {
            Button(showM3U ? L("إخفاء رابط M3U", "Hide M3U link") : L("عندي رابط M3U", "I have an M3U link")) {
                showM3U.toggle()
            }
            if showM3U {
                TextField("https://...", text: $m3uURL)
                    .textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
                Button(action: loginM3U) {
                    if isBusy { ProgressView() } else { Text(L("تحميل القائمة", "Load playlist")).bold() }
                }
                .buttonStyle(.borderedProminent).disabled(isBusy)
            }
        }
        .card()
    }

    // MARK: - Actions

    private func loginXtream() {
        var srv = server.trimmingCharacters(in: .whitespaces)
        if !srv.hasPrefix("http") { srv = "http://" + srv }
        guard !srv.isEmpty, !username.isEmpty else {
            errorText = L("اكتب السيرفر واسم المستخدم", "Enter the server and username")
            return
        }
        isBusy = true
        errorText = nil
        let acc = XtreamAccount(id: UUID().uuidString, kind: .xtream,
                                name: accountName.isEmpty ? L("سيرفري", "My server") : accountName,
                                server: srv, username: username)
        Task {
            do {
                _ = try await XtreamAPI.fetchLive(account: acc, password: password)
                await MainActor.run {
                    store.addAccount(acc, password: password)
                    Task { await store.loadLive() }
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    private func loginM3U() {
        guard !m3uURL.isEmpty else { return }
        isBusy = true
        errorText = nil
        let acc = XtreamAccount(id: UUID().uuidString, kind: .m3u,
                                name: L("قائمة M3U", "M3U playlist"),
                                server: m3uURL, username: "")
        Task {
            do {
                _ = try await XtreamAPI.fetchM3U(urlString: m3uURL)
                await MainActor.run {
                    store.addAccount(acc, password: nil)
                    Task { await store.loadLive() }
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }
}

private extension View {
    func card() -> some View {
        padding().background(Color.white.opacity(0.08)).cornerRadius(16)
    }
}
