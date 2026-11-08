//
//  TraktListEditorSheet.swift
//  FlixorMac
//
//  Create a Trakt list, or edit one's name, description and privacy.
//

import SwiftUI
import FlixorKit

enum TraktListEditorMode: Identifiable {
    case create
    case edit(TraktUserList)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let list): return "edit-\(list.id)"
        }
    }
}

struct TraktListEditorSheet: View {
    let mode: TraktListEditorMode
    /// Saves the trimmed values. Returns an error message, or nil on success.
    let onSave: (_ name: String, _ description: String, _ privacy: TraktListPrivacy) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.flixorTheme) private var theme

    @State private var name: String
    @State private var description: String
    @State private var privacy: TraktListPrivacy
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private let sheetWidth: CGFloat = 440

    init(
        mode: TraktListEditorMode,
        onSave: @escaping (_ name: String, _ description: String, _ privacy: TraktListPrivacy) async -> String?
    ) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let list) = mode {
            _name = State(initialValue: list.name)
            _description = State(initialValue: list.description ?? "")
            _privacy = State(initialValue: list.privacy.flatMap(TraktListPrivacy.init(rawValue:)) ?? .private)
        } else {
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _privacy = State(initialValue: .private)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Text(isEditing ? "Edit List" : "New List")
                .flixorFont(.title3, weight: .semibold)
                .foregroundStyle(theme.textPrimary)

            field("Name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($isNameFocused)
                    .accessibilityLabel("List name")
            }

            field("Description") {
                TextField("Optional", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .lineLimit(3...5)
                    .accessibilityLabel("List description")
            }

            field("Privacy") {
                Picker("Privacy", selection: $privacy) {
                    ForEach(TraktListPrivacy.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("List privacy")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .flixorFont(.callout)
                    .foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DS.Space.controlGap) {
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving")
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel")
                Button(isEditing ? "Save" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(!canSave)
                    .accessibilityLabel(isEditing ? "Save list" : "Create list")
            }
        }
        .padding(DS.Space.sheetPadding)
        .frame(width: sheetWidth)
        .onAppear { isNameFocused = true }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text(title)
                .flixorFont(.footnote, weight: .medium)
                .foregroundStyle(theme.textSecondary)
            content()
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let error = await onSave(trimmedName, trimmedDescription, privacy)
            isSaving = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}
