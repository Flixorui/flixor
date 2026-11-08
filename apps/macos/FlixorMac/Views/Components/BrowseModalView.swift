//
//  BrowseModalView.swift
//  FlixorMac
//
//  Netflix-style browse overlay for macOS.
//

import SwiftUI

struct BrowseModalView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: BrowseModalViewModel
    var onSelect: (MediaItem) -> Void

    private let cardWidth: CGFloat = 260

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            GeometryReader { proxy in
                let width = min(proxy.size.width - 160, 1024)
                let height = min(proxy.size.height - 160, max(proxy.size.height * 0.7, 700))

                VStack(spacing: 0) {
                    header
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.bottom, 20)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                }
                .frame(width: width, height: height, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 18)
                .padding(.horizontal, max(0, (proxy.size.width - width) / 2))
            }
            .padding(.vertical, 40)
        }
        .transition(.opacity.combined(with: .scale))
        .onExitCommand {
            dismiss()
        }
        .inPageModal(onDismiss: dismiss)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title.isEmpty ? "Browse" : viewModel.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                if let subtitle = viewModel.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.18))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            BrowseSkeletonGrid(cardWidth: cardWidth)
        case .error(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button(action: {
                    Task { await viewModel.reload() }
                }) {
                    Text("Retry")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.6))
                Text("No additional titles found.")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                VStack(spacing: 24) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: cardWidth), spacing: 24)],
                        spacing: 24
                    ) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            LandscapeCard(item: item, width: cardWidth) {
                                onSelect(item)
                                dismiss()
                            }
                            .onAppear {
                                if viewModel.shouldPrefetchItem(at: index) {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

// MARK: - Skeleton Grid

struct BrowseSkeletonGrid: View {
    let cardWidth: CGFloat
    private let placeholders = Array(0..<8)

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cardWidth), spacing: 24)],
                spacing: 24
            ) {
                ForEach(placeholders, id: \.self) { _ in
                    SkeletonView(width: cardWidth, height: cardWidth * 0.5, cornerRadius: 16)
                        .frame(width: cardWidth)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
