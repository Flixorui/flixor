import SwiftUI
import FlixorKit

struct TVMyListView: View {
    @ObservedObject private var viewModel: TVMyListViewModel
    @EnvironmentObject private var watchlistController: TVWatchlistController

    @State private var selectedItem: MediaItem?
    @FocusState private var focusedID: String?
    @FocusState private var focusedControlID: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: UX.itemSpacing), count: 5)

    init(viewModel: TVMyListViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            UltraBlurGradientBackground(colors: TVHomeViewModel.defaultRowColors)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                controls
                    .padding(.top, 20)

                content
                    .padding(.top, 20)
            }
            .padding(.top, 36)
        }
        .task {
            viewModel.attach(watchlistController)
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tvWatchlistDidChange)) { _ in
            Task { await viewModel.reload() }
        }
        .fullScreenCover(item: $selectedItem) { item in
            TVDetailsView(item: item)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("My List")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(viewModel.items.count) \(viewModel.items.count == 1 ? "title" : "titles")")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, UX.gridH)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            TextField("Search My List", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(width: 460)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

            HStack(spacing: 10) {
                ForEach(TVMyListViewModel.FilterType.allCases) { filter in
                    let key = "filter-\(filter.id)"
                    Button {
                        viewModel.filter = filter
                    } label: {
                        controlChip(
                            title: filter.title,
                            key: key,
                            isSelected: viewModel.filter == filter
                        )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedControlID, equals: key)
                    .focusEffectDisabled()
                }
            }

            Spacer()

            let sortKey = "sort"
            Button {
                cycleSort()
            } label: {
                controlActionChip(
                    title: "Sort",
                    value: viewModel.sort.title,
                    systemImage: "arrow.up.arrow.down",
                    key: sortKey
                )
            }
            .buttonStyle(.plain)
            .focused($focusedControlID, equals: sortKey)
            .focusEffectDisabled()
        }
        .padding(.horizontal, UX.gridH)
    }

    private func controlChip(title: String, key: String, isSelected: Bool) -> some View {
        let isFocused = focusedControlID == key
        let textColor: Color = isSelected ? .black : .white.opacity(isFocused ? 1.0 : 0.9)
        let backgroundColor: Color = {
            if isSelected {
                return .white
            } else if isFocused {
                return Color.white.opacity(0.35)
            } else {
                return Color.white.opacity(0.10)
            }
        }()
        let strokeColor: Color = {
            if isSelected {
                return .clear
            } else if isFocused {
                return Color.white.opacity(0.5)
            } else {
                return Color.white.opacity(0.2)
            }
        }()
        let strokeWidth: CGFloat = {
            if isSelected {
                return 0
            } else if isFocused {
                return 2
            } else {
                return 1
            }
        }()

        return Text(title)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0.2), radius: isFocused ? 16 : 8, y: isFocused ? 8 : 4)
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }

    private func controlActionChip(title: String, value: String, systemImage: String, key: String) -> some View {
        let isFocused = focusedControlID == key
        let titleColor: Color = .white.opacity(isFocused ? 0.85 : 0.6)
        let valueColor: Color = .white.opacity(isFocused ? 1.0 : 0.9)
        let backgroundColor: Color = isFocused ? Color.white.opacity(0.30) : Color.white.opacity(0.10)
        let strokeColor: Color = isFocused ? Color.white.opacity(0.4) : .clear
        let strokeWidth: CGFloat = isFocused ? 2 : 0

        return HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(titleColor)
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(titleColor)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: strokeWidth)
        )
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.35 : 0.0), radius: isFocused ? 12 : 0, y: isFocused ? 6 : 0)
        .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage, viewModel.visibleItems.isEmpty {
            errorView(error)
        } else if viewModel.isLoading && viewModel.visibleItems.isEmpty {
            skeletonGrid
        } else if viewModel.visibleItems.isEmpty {
            emptyState
        } else {
            gridContent
        }
    }

    private var skeletonGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: UX.railV) {
                ForEach(0..<15, id: \.self) { _ in
                    SkeletonPoster()
                        .frame(width: UX.posterWidth, height: UX.posterHeight)
                }
            }
            .padding(.horizontal, UX.gridH)
            .padding(.bottom, 80)
        }
    }

    private var gridContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: UX.railV) {
                ForEach(viewModel.visibleItems) { item in
                    let isFocused = focusedID == item.id
                    Button {
                        selectedItem = item.mediaItem
                    } label: {
                        ZStack(alignment: .topLeading) {
                            TVImage(url: posterURL(for: item), corner: UX.posterRadius, aspect: 2.0 / 3.0)
                                .frame(width: UX.posterWidth, height: UX.posterHeight)
                                .overlay(alignment: .bottomLeading) {
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.72), Color.clear],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: UX.posterRadius, style: .continuous))
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Text(item.title)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .padding(12)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: UX.posterRadius, style: .continuous)
                                        .stroke(isFocused ? Color.white.opacity(0.86) : Color.white.opacity(0.12), lineWidth: isFocused ? 3 : 1)
                                )

                            sourceBadge(item.source)
                                .padding(10)
                        }
                    }
                    .buttonStyle(.plain)
                    .focusable(true)
                    .focused($focusedID, equals: item.id)
                    .scaleEffect(isFocused ? UX.focusScale : 1.0)
                    .shadow(color: .black.opacity(isFocused ? 0.44 : 0.24), radius: isFocused ? 18 : 9, y: isFocused ? 9 : 4)
                    .animation(.easeOut(duration: UX.focusDur), value: isFocused)
                    .contextMenu {
                        Button("View Details") {
                            selectedItem = item.mediaItem
                        }
                        Button("Remove from My List", role: .destructive) {
                            Task { await viewModel.remove(item: item) }
                        }
                    }
                }
            }
            .padding(.horizontal, UX.gridH)
            .padding(.bottom, 100)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("Your list is empty")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
            Text("Add movies and TV shows from Details.")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Unable to load My List")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
            Button {
                Task { await viewModel.reload() }
            } label: {
                Text("Retry")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourceBadge(_ source: TVMyListViewModel.Source) -> some View {
        let text: String
        let color: Color

        switch source {
        case .plex:
            text = "Plex"
            color = Color.orange.opacity(0.92)
        case .trakt:
            text = "Trakt"
            color = Color.blue.opacity(0.92)
        case .both:
            text = "Plex + Trakt"
            color = Color.green.opacity(0.88)
        }

        return Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color, in: Capsule())
    }

    private func cycleSort() {
        let all = TVMyListViewModel.SortOption.allCases
        guard let index = all.firstIndex(of: viewModel.sort) else { return }
        let next = all[(index + 1) % all.count]
        viewModel.sort = next
    }

    private func posterURL(for item: TVMyListViewModel.WatchlistItem) -> URL? {
        if let imageURL = item.imageURL {
            return imageURL
        }
        return ImageService.shared.thumbURL(for: item.mediaItem, width: 360, height: 540)
    }
}
