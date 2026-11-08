//
//  DetailsRatingSheet.swift
//  FlixorMac
//
//  Small sheet to rate a title on Trakt: 1-10 shown as five stars with halves.
//  The current rating is preselected; "Remove rating" clears it.
//

import SwiftUI

struct DetailsRatingSheet: View {
    let title: String
    let initialRating: Int?
    let onSave: (Int) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var selection: Int
    @State private var hoverValue: Int?

    private static let starSize: CGFloat = 34
    private static let starSpacing: CGFloat = DS.Space.s8

    init(
        title: String,
        initialRating: Int?,
        onSave: @escaping (Int) -> Void,
        onRemove: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.initialRating = initialRating
        self.onSave = onSave
        self.onRemove = onRemove
        self.onCancel = onCancel
        _selection = State(initialValue: initialRating ?? 0)
    }

    private var displayedValue: Int { hoverValue ?? selection }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s20) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("Rate on Trakt")
                    .flixorFont(.title3)
                    .foregroundStyle(theme.textPrimary)
                Text(title)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }

            VStack(spacing: DS.Space.s12) {
                stars
                Text(displayedValue > 0 ? "\(displayedValue)/10 · \(Self.label(for: displayedValue))" : "Choose a rating")
                    .flixorFont(.callout, weight: .medium)
                    .foregroundStyle(displayedValue > 0 ? theme.textPrimary : theme.textTertiary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: DS.Space.s12) {
                if initialRating != nil {
                    Button(role: .destructive, action: onRemove) {
                        Text("Remove rating")
                    }
                    .accessibilityLabel("Remove rating")
                }
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == 0 || selection == initialRating)
            }
        }
        .padding(DS.Space.sheetPadding)
        .frame(width: 380)
        .background(theme.surfaceElevated)
    }

    // MARK: - Stars

    private var stars: some View {
        HStack(spacing: Self.starSpacing) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: symbol(forStar: index))
                    .font(.flixorIcon(Self.starSize))
                    .foregroundStyle(displayedValue >= index * 2 - 1 ? theme.warning : theme.textTertiary)
                    .frame(width: Self.starSize, height: Self.starSize)
                    .overlay {
                        // Left half = odd value (half star), right half = full star.
                        HStack(spacing: 0) {
                            halfTarget(value: index * 2 - 1)
                            halfTarget(value: index * 2)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(selection > 0 ? "\(selection) out of 10" : "Not rated")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = min(10, selection + 1)
            case .decrement: selection = max(1, selection - 1)
            @unknown default: break
            }
        }
    }

    private func halfTarget(value: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { selection = value }
            .onHover { inside in
                if inside {
                    hoverValue = value
                } else if hoverValue == value {
                    hoverValue = nil
                }
            }
    }

    private func symbol(forStar index: Int) -> String {
        let value = displayedValue
        if value >= index * 2 { return "star.fill" }
        if value == index * 2 - 1 { return "star.leadinghalf.filled" }
        return "star"
    }

    static func label(for value: Int) -> String {
        switch value {
        case 1: return "Awful"
        case 2: return "Terrible"
        case 3: return "Bad"
        case 4: return "Poor"
        case 5: return "Meh"
        case 6: return "Fair"
        case 7: return "Good"
        case 8: return "Great"
        case 9: return "Superb"
        default: return "Masterpiece"
        }
    }
}
