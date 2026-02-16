import SwiftUI

struct TVNewPopularHero: View {
    let data: TVNewPopularViewModel.HeroData
    let onPlay: () -> Void
    let onMoreInfo: () -> Void
    let onMyList: () -> Void
    let onTrailer: () -> Void

    @FocusState private var focusedAction: Action?

    private enum Action: Hashable {
        case play
        case trailer
        case myList
        case info
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let backdropURL = data.backdropURL {
                CachedAsyncImage(url: backdropURL, contentMode: .fill) {
                    Color.black
                }
                .frame(maxWidth: .infinity)
                .frame(height: UX.heroFullBleedHeight)
                .clipped()
            } else {
                LinearGradient(
                    colors: [Color.black, Color.gray.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: UX.heroFullBleedHeight)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.76), Color.black.opacity(0.42), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: UX.heroFullBleedHeight)

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: UX.heroFullBleedHeight)

            VStack(alignment: .leading, spacing: 14) {
                if let logoURL = data.logoURL {
                    CachedAsyncImage(url: logoURL, contentMode: .fit) {
                        Text(data.title)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: 460, maxHeight: 140, alignment: .leading)
                } else {
                    Text(data.title)
                        .font(.system(size: 60, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: 580, alignment: .leading)
                }

                HStack(spacing: 10) {
                    if let year = data.year {
                        Text(year)
                    }
                    if let runtime = data.runtime {
                        Text("\(runtime)m")
                    }
                    if let rating = data.rating {
                        Text(rating)
                    }
                }
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))

                if !data.genres.isEmpty {
                    Text(data.genres.prefix(3).joined(separator: " • "))
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Text(data.overview)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .frame(maxWidth: 700, alignment: .leading)

                HStack(spacing: 14) {
                    actionButton(title: "Play", systemImage: "play.fill", focused: .play, action: onPlay)
                    actionButton(title: "Trailer", systemImage: "play.rectangle.fill", focused: .trailer, action: onTrailer)
                    actionButton(title: "My List", systemImage: "plus", focused: .myList, action: onMyList)
                    actionButton(title: "More Info", systemImage: "info.circle", focused: .info, action: onMoreInfo)
                }
            }
            .padding(.leading, UX.heroContentLeadingInset)
            .padding(.top, 36)
            .padding(.bottom, UX.heroContentBottomInset)
        }
        .frame(height: UX.heroFullBleedHeight)
        .clipped()
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
    }

    private func actionButton(title: String, systemImage: String, focused: Action, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(focusedAction == focused ? Color.black : Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(focusedAction == focused ? Color.white : Color.white.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedAction, equals: focused)
        .shadow(color: .black.opacity(focusedAction == focused ? 0.42 : 0.2), radius: focusedAction == focused ? 12 : 4, y: 4)
        .animation(.easeOut(duration: UX.focusDur), value: focusedAction)
    }
}
