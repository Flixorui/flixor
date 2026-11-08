//
//  PlayerExtraOverlays.swift
//  FlixorMac
//
//  Player HUD pieces: stream engine status pill, 2x badge, keyboard feedback,
//  the aspect panel and the keyboard shortcuts overlay.
//

import SwiftUI

// MARK: - Status stack

/// Top-centre status, visible with or without the controls. Never takes clicks.
struct PlayerStatusStack: View {
    let status: String?
    let isSpeedBoostActive: Bool
    let feedback: String?

    var body: some View {
        VStack(spacing: DS.Space.s8) {
            if isSpeedBoostActive {
                HStack(spacing: DS.Space.s4) {
                    Image(systemName: "forward.fill")
                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                    Text("2×")
                        .font(.flixor(.body, weight: .bold))
                }
                .modifier(PlayerPillStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playing at double speed")
                .transition(.opacity)
            }

            if let status {
                HStack(spacing: DS.Space.s8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status)
                        .font(.flixor(.footnote, weight: .medium))
                        .lineLimit(2)
                }
                .modifier(PlayerPillStyle())
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }

            if let feedback {
                Text(feedback)
                    .font(.flixor(.footnote, weight: .medium))
                    .modifier(PlayerPillStyle())
                    .transition(.opacity)
            }

            Spacer()
        }
        .padding(.top, DS.Space.s64)
        .padding(.horizontal, DS.Space.s40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(DS.Motion.standard, value: isSpeedBoostActive)
        .animation(DS.Motion.standard, value: status)
        .animation(DS.Motion.quick, value: feedback)
    }
}

private struct PlayerPillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s6)
            .background(Color.black.opacity(DS.Opacity.scrimHeavy), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(DS.Opacity.selected), lineWidth: DS.Border.thin))
    }
}

// MARK: - Aspect panel

/// Aspect modes and zoom steps. No scrim, so the change to the picture stays visible.
struct PlayerAspectPanel: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    @Environment(\.flixorTheme) private var theme

    private var canZoomIn: Bool {
        viewModel.aspectMode != .zoom || viewModel.zoomStep < PlayerAspectMode.zoomFactors.count - 1
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            card
                .padding(.trailing, DS.Space.s32)
                .padding(.bottom, 140)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            ForEach(PlayerAspectMode.allCases) { mode in
                modeRow(mode)
            }

            Divider()
                .background(Color.white.opacity(DS.Opacity.selected))
                .padding(.vertical, DS.Space.s4)

            HStack(spacing: DS.Space.s8) {
                Text("Zoom")
                    .font(.flixor(.callout))
                    .foregroundStyle(.white.opacity(DS.Opacity.strong))

                Spacer()

                zoomButton(systemImage: "minus", label: "Zoom out", isEnabled: viewModel.aspectMode == .zoom) {
                    viewModel.zoomOut()
                }

                Text(viewModel.aspectMode == .zoom ? String(format: "%g×", viewModel.zoomFactor) : "–")
                    .font(.flixor(.callout, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(DS.Opacity.secondary))
                    .frame(width: 48)

                zoomButton(systemImage: "plus", label: "Zoom in", isEnabled: canZoomIn) {
                    viewModel.zoomIn()
                }
            }
            .padding(.horizontal, DS.Space.s10)
            .padding(.vertical, DS.Space.s4)
        }
        .padding(DS.Space.s8)
        .frame(width: 260)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.poster))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.poster).strokeBorder(Color.white.opacity(DS.Opacity.selected), lineWidth: DS.Border.thin))
        .flixorShadow(.modal)
    }

    private func modeRow(_ mode: PlayerAspectMode) -> some View {
        let isSelected = viewModel.aspectMode == mode
        return Button(action: { viewModel.setAspectMode(mode) }) {
            HStack(spacing: DS.Space.s10) {
                Image(systemName: mode.systemImage)
                    .font(.flixorIcon(DS.Icon.sm))
                    .foregroundStyle(isSelected ? theme.accent : .white.opacity(DS.Opacity.secondary))
                    .frame(width: DS.Icon.lg)

                Text(mode.displayName)
                    .font(.flixor(.callout, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isSelected ? DS.Opacity.visible : DS.Opacity.secondary))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, DS.Space.s10)
            .padding(.vertical, DS.Space.s8)
            .background(isSelected ? Color.white.opacity(DS.Opacity.hover) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func zoomButton(systemImage: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                .foregroundStyle(.white.opacity(isEnabled ? DS.Opacity.visible : DS.Opacity.disabled))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(DS.Opacity.selected))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Keyboard shortcuts overlay

struct PlayerShortcutsOverlay: View {
    let smallSeek: Int
    let largeSeek: Int
    let onClose: () -> Void

    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys }
    }

    private var shortcuts: [Shortcut] {
        [
            Shortcut(keys: "Space / K", action: "Play or pause"),
            Shortcut(keys: "Hold Space", action: "Play at 2×"),
            Shortcut(keys: "← →", action: "Seek \(smallSeek) s"),
            Shortcut(keys: "⇧ ← →", action: "Seek \(largeSeek) s"),
            Shortcut(keys: "J / L", action: "Seek \(largeSeek) s"),
            Shortcut(keys: "⌥ ← →", action: "Seek 2 s"),
            Shortcut(keys: "↑ ↓", action: "Volume"),
            Shortcut(keys: "M", action: "Mute"),
            Shortcut(keys: "[ ]", action: "Previous or next chapter"),
            Shortcut(keys: "⇧ N", action: "Next episode"),
            Shortcut(keys: "V", action: "Next subtitle track"),
            Shortcut(keys: "B", action: "Next audio track"),
            Shortcut(keys: "G / H", action: "Subtitle offset −/+ 0.1 s"),
            Shortcut(keys: "< >", action: "Slower or faster"),
            Shortcut(keys: "/", action: "Normal speed"),
            Shortcut(keys: "A", action: "Change aspect"),
            Shortcut(keys: "F", action: "Full screen"),
            Shortcut(keys: "P", action: "Picture in Picture"),
            Shortcut(keys: "I", action: "Performance stats"),
            Shortcut(keys: "?", action: "Show or hide this list"),
            Shortcut(keys: "Esc", action: "Exit full screen or close"),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(DS.Opacity.scrimMedium)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: DS.Space.s12) {
                HStack {
                    Text("Keyboard Shortcuts")
                        .font(.flixor(.headline, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                            .foregroundStyle(.white.opacity(DS.Opacity.secondary))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close keyboard shortcuts")
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240), spacing: DS.Space.s24, alignment: .top)],
                        alignment: .leading,
                        spacing: DS.Space.s8
                    ) {
                        ForEach(shortcuts) { shortcut in
                            HStack(spacing: DS.Space.s12) {
                                Text(shortcut.keys)
                                    .font(.flixor(.footnote, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .frame(width: 84, alignment: .leading)
                                Text(shortcut.action)
                                    .font(.flixor(.footnote))
                                    .foregroundStyle(.white.opacity(DS.Opacity.secondary))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
            .padding(DS.Space.sheetPadding)
            .frame(maxWidth: 640)
            .background(Color.black.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sheet))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.sheet).strokeBorder(Color.white.opacity(DS.Opacity.selected), lineWidth: DS.Border.thin))
            .flixorShadow(.modal)
            .padding(DS.Space.s40)
        }
    }
}
