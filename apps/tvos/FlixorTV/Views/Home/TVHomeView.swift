import SwiftUI
import FlixorKit

struct TVHomeView: View {
    @StateObject private var vm = TVHomeViewModel()
    @Namespace private var contentFocusNS
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 40) {
                if let first = vm.billboardItems.first {
                    TVBillboardView(item: first, focusNS: contentFocusNS, defaultFocus: true)
                        .padding(.top, 12)
                } else {
                    placeholderBillboard
                        .padding(.top, 12)
                }

                // Rows
                if !vm.trending.isEmpty {
                    TVCarouselRow(title: "My List", items: vm.trending, kind: .poster, focusNS: contentFocusNS, defaultFocus: true)
                }
                if !vm.continueWatching.isEmpty {
                    TVCarouselRow(title: "Continue Watching", items: vm.continueWatching, kind: .landscape)
                }
                if !vm.recentlyAdded.isEmpty {
                    TVCarouselRow(title: "New on Flixor", items: vm.recentlyAdded, kind: .landscape)
                }

                #if DEBUG
                if let msg = vm.debugMessage {
                    Text(msg).foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 40)
                }
                #endif
            }
            .padding(.bottom, 80)
        }
        .background(Color.black)
        .focusScope(contentFocusNS)
        .task { await vm.load() }
        .onChange(of: session.isAuthenticated) { authed in
            if authed { Task { await vm.load() } }
        }
    }

    private var placeholderBillboard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(height: 540)
            .padding(.horizontal, 40)
    }
}
