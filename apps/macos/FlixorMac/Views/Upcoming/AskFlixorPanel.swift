//
//  AskFlixorPanel.swift
//  FlixorMac
//
//  The Ask Flixor chat panel, on the right of the window (⌘J). Answers come
//  from AskFlixorModel; titles they name are cards that open Details.
//

import SwiftUI

struct AskFlixorPanel: View {
    @ObservedObject var model: AskFlixorModel
    let onClose: () -> Void

    @ObservedObject private var settings = AISettings.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    static let width: CGFloat = 400
    private static let tint = Color(hex: 0xA78BFA)

    private var engineLabel: String {
        switch settings.engine {
        case .apple: return String(localized: "Apple Intelligence · on this Mac")
        case .openAI: return "OpenAI · \(settings.openAIModel)"
        case .anthropic: return "Anthropic · \(settings.model(for: .anthropic, quick: false))"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s14) {
                        if model.messages.isEmpty { emptyState }
                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if model.isSending {
                            HStack(spacing: DS.Space.s8) {
                                ProgressView().controlSize(.small)
                                Text("Looking it up…").font(.flixor(.footnote)).foregroundStyle(theme.textSecondary)
                            }
                            .id("sending")
                        }
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.flixor(.footnote))
                                .foregroundStyle(theme.warning)
                        }
                    }
                    .padding(DS.Space.s16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.messages.count) { _ in
                    withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: model.isSending) { sending in
                    if sending { withAnimation { proxy.scrollTo("sending", anchor: .bottom) } }
                }
            }
            if model.messages.isEmpty { suggestions }
            input
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color(hex: 0x0B0B0D).opacity(0.97))
        .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
        .shadow(color: .black.opacity(0.5), radius: 24, x: -8)
        .onAppear { inputFocused = true }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: DS.Space.s8) {
            Image(systemName: "sparkles").foregroundStyle(Self.tint)
            Text("Ask Flixor").font(.flixor(.headline, weight: .bold))
            Spacer()
            Text(engineLabel).font(.system(size: 11)).foregroundStyle(theme.textTertiary).lineLimit(1)
            if !model.messages.isEmpty {
                Button { model.clear() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless)
                    .help("New conversation")
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Close (⌘J)")
        }
        .padding(.horizontal, DS.Space.s16)
        .padding(.top, DS.Space.s40)
        .padding(.bottom, DS.Space.s12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text("Ask about movies, shows and your library.")
                .font(.flixor(.callout, weight: .semibold))
            Text("Answers use your watchlist, history, Plex library and TMDB. Titles it names are real cards you can open.")
                .font(.flixor(.footnote))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.top, DS.Space.s8)
    }

    @ViewBuilder
    private func bubble(_ message: AskMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.flixor(.callout))
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.vertical, DS.Space.s8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x2A2A2F)))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                if !message.used.isEmpty {
                    Text("Used: " + message.used.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                Text(LocalizedStringKey(message.text))
                    .font(.flixor(.callout))
                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(message.cards) { card in
                    AskCardRow(card: card) {
                        router.push(DetailsNavigationItem(item: card.item), on: mainViewState.selectedTab)
                    }
                }
            }
        }
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s6) {
                ForEach(AskFlixorModel.suggestions, id: \.self) { text in
                    Button { model.send(text) } label: {
                        Text(text)
                            .font(.flixor(.footnote, weight: .semibold))
                            .padding(.horizontal, DS.Space.s10)
                            .padding(.vertical, DS.Space.s6)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.s16)
        }
        .padding(.bottom, DS.Space.s8)
    }

    private var input: some View {
        HStack(spacing: DS.Space.s8) {
            Image(systemName: "sparkles").foregroundStyle(Self.tint)
            TextField("Ask about movies, shows, your library…", text: $draft)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(send)
                .disabled(model.isSending)
            Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isSending)
        }
        .padding(.horizontal, DS.Space.s12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .padding(DS.Space.s16)
    }

    private func send() {
        let text = draft
        draft = ""
        model.send(text)
    }
}

private struct AskCardRow: View {
    let card: AskTitleCard
    let onOpen: () -> Void
    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s10) {
                CachedAsyncImage(url: card.posterURL, maxPixelSize: 120)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.item.title).font(.flixor(.callout, weight: .semibold)).lineLimit(1)
                    Text(card.subtitle).font(.flixor(.footnote)).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textTertiary)
            }
            .padding(DS.Space.s6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isHovered ? 0.09 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(card.item.title)")
    }
}

/// The ✦ button in the window corner that opens Ask Flixor.
struct AskFlixorLauncher: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color(hex: 0x7C3AED).opacity(isHovered ? 1 : 0.85)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Ask Flixor (⌘J)")
        .accessibilityLabel(Text("Ask Flixor"))
    }
}
