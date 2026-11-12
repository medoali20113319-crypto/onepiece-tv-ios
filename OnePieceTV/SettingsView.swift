// SettingsView.swift — language, dubbing, accounts, about.
// (Android v4.8: «اى حاجه فيها اعداد حطها جوه الاعداد».)

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section(L("اللغة", "Language")) {
                Picker(L("لغة البرنامج", "App language"), selection: $store.languageRaw) {
                    Text("العربية").tag("ar")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            }

            Section(L("الدبلجة", "Dubbing")) {
                Toggle(L("🎙️ دبلجة لايف (إنجليزي → عربي)", "🎙️ Live dubbing (English → Arabic)"), isOn: $store.dubbingEnabled)
                Text(L("بتشتغل على الجهاز نفسه: تعرّف على الكلام الإنجليزي وترجمته ونطقه بالعربي. لو الصوت العربي أو حزمة الترجمة مش نازلة، الدبلجة مش هتشتغل ومش هتكتم الصوت الأصلي.", "Runs fully on-device: English speech recognition, translation and Arabic speech. If the Arabic voice or the translation pack is missing, dubbing stays off and the original audio is not muted."))
                    .font(.caption).foregroundColor(.secondary)
            }

            Section(L("الحسابات", "Accounts")) {
                ForEach(store.accounts) { acc in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(acc.name).bold()
                            Text(acc.kind == .xtream ? acc.server : acc.server)
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if store.currentAccountId == acc.id {
                            Text(L("الحالي", "Current")).font(.caption).foregroundColor(.yellow)
                        } else {
                            Button(L("اختيار", "Select")) { store.selectAccount(acc) }
                        }
                    }
                }
            }

            Section(L("عن البرنامج", "About")) {
                HStack {
                    Text(L("الاسم", "Name"))
                    Spacer()
                    Text("One Piece TV")
                }
                HStack {
                    Text(L("الإصدار", "Version"))
                    Spacer()
                    Text(store.appVersion)
                }
                Text(L("مشغّل IPTV لاشتراكك الخاص — بث مباشر، أفلام ومسلسلات. بيانات الدخول بتتحفظ على جهازك بس.", "An IPTV player for your own subscription — live TV, movies and series. Your login details stay only on your device."))
                    .font(.caption).foregroundColor(.secondary)
                Text(L("ملحوظة: قسم الدش (تيونر USB) مش موجود في نسخة الآيفون — نظام آبل مبيسمحش بيه.", "Note: the dish section (USB tuner) is not in the iPhone version — Apple does not allow it."))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle(L("الإعدادات", "Settings"))
    }
}
