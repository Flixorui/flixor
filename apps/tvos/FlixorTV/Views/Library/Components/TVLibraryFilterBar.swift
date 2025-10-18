//
//  TVLibraryFilterBar.swift
//  FlixorTV
//
//  Filter bar for library with section pills (Phase 1: Section switching only)
//

import SwiftUI

struct TVLibraryFilterBar: View {
    @ObservedObject var viewModel: TVLibraryViewModel
    @Namespace private var filterNS

    var body: some View {
        VStack(spacing: 16) {
            // Section pills (horizontal scroll)
            if !viewModel.sections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.sections) { section in
                            SectionPill(
                                section: section,
                                isActive: viewModel.activeSection?.id == section.id,
                                onTap: {
                                    viewModel.selectSection(section)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 2)
                }
                .frame(height: 70)
                .focusSection()
            }
        }
        .padding(.top, 32)
        .padding(.bottom, 16)
    }
}

// MARK: - Section Pill Component

private struct SectionPill: View {
    let section: TVLibraryViewModel.LibrarySectionSummary
    let isActive: Bool
    let onTap: () -> Void

    @State private var isFocused: Bool = false

    var body: some View {
        Button(action: onTap) {
            Text(section.title.uppercased())
                .font(.system(size: 22, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(textColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )
        }
        .buttonStyle(TVFocusButtonStyle(isFocused: $isFocused))
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0.2), radius: isFocused ? 16 : 8, y: isFocused ? 8 : 4)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }

    private var textColor: Color {
        if isActive {
            return .black
        } else {
            return .white.opacity(isFocused ? 1.0 : 0.9)
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return .white
        } else if isFocused {
            return Color.white.opacity(0.35)
        } else {
            return Color.white.opacity(0.10)
        }
    }

    private var strokeColor: Color {
        if isActive {
            return .clear
        } else if isFocused {
            return Color.white.opacity(0.5)
        } else {
            return Color.white.opacity(0.2)
        }
    }

    private var strokeWidth: CGFloat {
        if isActive {
            return 0
        } else if isFocused {
            return 2
        } else {
            return 1
        }
    }
}

// MARK: - Custom Button Style for Focus Tracking

private struct TVFocusButtonStyle: ButtonStyle {
    @Binding var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusable(true) { focused in
                isFocused = focused
            }
    }
}
