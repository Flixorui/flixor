//
//  FlixorTheme+Chrome.swift
//  FlixorMac
//
//  Surfaces for screens whose default look doesn't match a theme token:
//  they keep their own colour unless pure black is on.
//

import SwiftUI
import AppKit

extension FlixorTheme {
    /// `literal` in the default look; `black` (the page background unless
    /// given) when pure black is on.
    func chromeColor(default literal: Color, pureBlack black: Color? = nil) -> Color {
        pureBlack ? (black ?? background) : literal
    }

    /// Settings window and settings sheets.
    var settingsWindowBackground: Color {
        chromeColor(default: Color(NSColor.windowBackgroundColor))
    }

    /// Grouped cards and chips in settings.
    var settingsGroupBackground: Color {
        chromeColor(default: Color(NSColor.controlBackgroundColor), pureBlack: surface)
    }

    /// Text fields in settings, which sit on top of a group card.
    var settingsFieldBackground: Color {
        chromeColor(default: Color(NSColor.textBackgroundColor), pureBlack: surfaceElevated)
    }

    /// Panels and cards floating over the video. Not for scrims.
    func playerPanelBackground(opacity: Double = 0.95) -> Color {
        chromeColor(default: Color.black.opacity(opacity))
    }
}

extension View {
    /// Paints the page background behind a sheet that otherwise uses the
    /// system window colour. Does nothing unless pure black is on.
    func pureBlackSheetBackground() -> some View {
        modifier(PureBlackSheetBackgroundModifier())
    }
}

private struct PureBlackSheetBackgroundModifier: ViewModifier {
    @Environment(\.flixorTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.pureBlack ? theme.background.ignoresSafeArea() : nil)
    }
}
