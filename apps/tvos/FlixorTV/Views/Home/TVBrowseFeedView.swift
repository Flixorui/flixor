import SwiftUI
import FlixorKit

struct TVBrowseFeedView: View {
    let section: TVHomeSectionDescriptor
    var onSelect: ((MediaItem) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @Environment(\.tvCardVisualTokens) private var cardTokens

    @State private var selectedItem: MediaItem?
    @FocusState private var focusedID: String?

    private var isLandscape: Bool {
        (section.preferredRowKind ?? .poster) == .landscape
    }

    private var columns: [GridItem] {
        if isLandscape {
            return Array(repeating: GridItem(.flexible(minimum: 460, maximum: 620), spacing: 28), count: 2)
        }

        let count = max(3, profileSettings.posterWidthPreset.libraryGridColumnCount)
        return Array(repeating: GridItem(.flexible(minimum: 220, maximum: 320), spacing: 24), count: count)
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            UltraBlurGradientBackground(colors: TVHomeViewModel.defaultRowColors, opacity: 0.28)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(section.items, id: \.id) { item in
                            browseCard(for: item)
                        }
                    }
                    .padding(.horizontal, UX.gridH)
                    .padding(.bottom, 120)
                }
                .padding(.top, 54)
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            TVDetailsView(item: item)
        }
        .onAppear {
            if focusedID == nil {
                focusedID = focusCoordinator.lastFocusedItem(screen: .home, sectionID: section.id) ?? section.items.first?.id
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(section.title)
                    .font(typography.hero)
                    .foregroundStyle(theme.textPrimary)

                Text("\(section.items.count) titles")
                    .font(typography.body)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle.fill")
                    .font(typography.label)
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(theme.surfaceGlass, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(theme.strokeDefault, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, UX.gridH)
    }

    @ViewBuilder
    private func browseCard(for item: MediaItem) -> some View {
        let isFocused = focusedID == item.id
        Button {
            if let onSelect {
                onSelect(item)
            } else {
                selectedItem = item
            }
        } label: {
            Group {
                if isLandscape {
                    TVLandscapeCard(
                        item: item,
                        showBadges: true,
                        isFocused: isFocused,
                        focusOutlineOnFocus: true
                    )
                    .frame(height: UX.landscapeHeight + 8)
                } else {
                    TVPosterCard(
                        item: item,
                        isFocused: isFocused,
                        respectLibraryTitles: true
                    )
                    .frame(width: UX.posterWidth * profileSettings.posterWidthMultiplier, height: UX.posterHeight * profileSettings.posterWidthMultiplier)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: isLandscape ? cardTokens.landscapeRadius : profileSettings.posterCornerRadius, style: .continuous)
                    .stroke(isFocused ? theme.strokeFocused : Color.clear, lineWidth: isFocused ? cardTokens.focusedStrokeWidth : 0)
            )
            .scaleEffect(isFocused ? cardTokens.focusedScale : 1.0)
            .shadow(
                color: .black.opacity(isFocused ? 0.5 : 0.24),
                radius: isFocused ? cardTokens.focusedShadowRadius : cardTokens.unfocusedShadowRadius,
                y: isFocused ? cardTokens.focusedShadowYOffset : cardTokens.unfocusedShadowYOffset
            )
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedID, equals: item.id)
        .onChange(of: isFocused) { focused in
            if focused {
                focusCoordinator.remember(screen: .home, sectionID: section.id, itemID: item.id)
            }
        }
    }
}
