import SwiftUI

/// Debug: menu of dark background hex codes. Tapping one opens a profile-style preview with that background.
struct BlackScreensMenuView: View {
    @State private var selectedHexForModal: String?

    /// Expanded grayscale palette for dark-theme comparison.
    private static let colorCodes: [String] = [
        "050505",
        "080808",
        "0A0A0A",
        "1B1B1B",
        "0C0C0C",
        "101010",
        "121212",
        "141414",
        "161616",
        "171717",
        "181818",
        "191919",
        "1C1C1C",
        "1E1E1E",
        "202020",
        "212121",
        "222222",
        "232323",
        "242424",
        "252525",
        "272727",
        "292929",
        "2B2B2B",
        "2D2D2D",
        "2F2F2F",
        "303030",
        "313638",
        "343434",
        "383838",
        "3D3D3D",
        "424242",
        "4A4A4A",
        "545454",
        "002147"
    ]

    var body: some View {
        List {
            Section {
                Text("Tap a code to see the profile layout on that dark background.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            } header: {
                Text("Preview")
            }
            Section {
                ForEach(Self.colorCodes, id: \.self) { hex in
                    HStack(spacing: Theme.Spacing.md) {
                        Button {
                            selectedHexForModal = hex
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: hex))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Theme.Colors.glassBorder, lineWidth: 1)
                                    )
                                Text(hex)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        NavigationLink(destination: BlackScreenProfileView(hex: hex)) {
                            Text("Profile")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.primaryColor)
                        }
                    }
                }
            } header: {
                Text("Colour codes")
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Black screens")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: Binding(
            get: { selectedHexForModal != nil },
            set: { if !$0 { selectedHexForModal = nil } }
        )) {
            if let hex = selectedHexForModal {
                BlackScreenModalSheetsPreview(hex: hex)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct BlackScreenModalSheetsPreview: View {
    let hex: String
    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Text("Modal sheet tester")
                    .font(Theme.Typography.title3)
                    .foregroundColor(.white)
                Text("Background: #\(hex)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.white.opacity(0.75))

                Button("Open medium sheet") { selectedDetent = .medium }
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.primaryColor)
                    .clipShape(Capsule())
                Button("Open large sheet") { selectedDetent = .large }
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.primaryColor.opacity(0.75))
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: hex).ignoresSafeArea())
            .navigationTitle("Sheets on #\(hex)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }
}

