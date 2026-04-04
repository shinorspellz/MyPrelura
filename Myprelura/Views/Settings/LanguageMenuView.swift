//
//  LanguageMenuView.swift
//  Prelura-swift
//
//  App language: English or Greek. Selection is stored and applied app-wide.
//

import SwiftUI

struct LanguageMenuView: View {
    @AppStorage(kAppLanguage) private var appLanguage: String = "en"
    @State private var showLanguageAppliedAlert = false

    private let options: [(id: String, titleKey: String)] = [
        ("en", "English"),
        ("el", "Greek")
    ]

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.id) { option in
                    Button {
                        let previous = appLanguage
                        appLanguage = option.id
                        if previous != option.id {
                            showLanguageAppliedAlert = true
                        }
                    } label: {
                        HStack {
                            Text(L10n.string(option.titleKey))
                                .foregroundColor(Theme.Colors.primaryText)
                            Spacer()
                            if appLanguage == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.primaryColor)
                            }
                        }
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
            } footer: {
                Text(L10n.string("Greek displays the app in Greek."))
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert(L10n.string("Language updated"), isPresented: $showLanguageAppliedAlert) {
            Button(L10n.string("OK"), role: .cancel) { }
        } message: {
            Text(L10n.string("The app will use the selected language the next time you open it. Close and reopen the app to see the change."))
        }
    }
}

#Preview {
    NavigationStack {
        LanguageMenuView()
    }
}
