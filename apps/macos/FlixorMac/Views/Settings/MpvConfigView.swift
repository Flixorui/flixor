//
//  MpvConfigView.swift
//  FlixorMac
//
//  Custom MPV configuration editor with presets
//

import SwiftUI

struct MpvConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MpvConfigEntry] = []
    @State private var presets: [MpvPreset] = []
    @State private var showAddSheet = false
    @State private var editingEntry: MpvConfigEntry?
    @State private var showSavePresetSheet = false
    @State private var showDeleteConfirmation = false
    @State private var presetToDelete: MpvPreset?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MPV Configuration")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Add custom MPV properties for advanced playback control")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Presets Section
                    if !presets.isEmpty {
                        SettingsSectionHeader(title: "Presets")
                        SettingsGroupCard {
                            ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                                PresetRow(
                                    preset: preset,
                                    isLast: index == presets.count - 1,
                                    onLoad: { loadPreset(preset) },
                                    onDelete: {
                                        presetToDelete = preset
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    }

                    // Save as Preset Button
                    if !entries.isEmpty {
                        Button(action: { showSavePresetSheet = true }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save Current as Preset")
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    // Properties Section
                    SettingsSectionHeader(title: "MPV Properties")
                    SettingsGroupCard {
                        HStack {
                            Text("Custom Properties")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button(action: { showAddSheet = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)

                        if entries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.secondary)
                                Text("No custom properties")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text("Add MPV properties like 'hwdec', 'deband', etc.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            Divider()
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                MpvConfigEntryRow(
                                    entry: binding(for: entry),
                                    isLast: index == entries.count - 1,
                                    onEdit: { editingEntry = entry },
                                    onDelete: { deleteEntry(entry) }
                                )
                            }
                        }
                    }

                    // Help text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Common Properties")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Group {
                            helpRow(key: "hwdec", value: "videotoolbox", description: "Hardware decoding")
                            helpRow(key: "deband", value: "yes", description: "Remove color banding")
                            helpRow(key: "scale", value: "lanczos", description: "Upscaling algorithm")
                            helpRow(key: "target-colorspace-hint", value: "yes", description: "HDR passthrough")
                            helpRow(key: "video-sync", value: "display-resample", description: "Smooth motion")
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(20)
            }
        }
        .frame(width: 550, height: 600)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .onAppear(perform: loadData)
        .sheet(isPresented: $showAddSheet) {
            MpvConfigEntryEditor(onSave: addEntry)
        }
        .sheet(item: $editingEntry) { entry in
            MpvConfigEntryEditor(entry: entry, onSave: updateEntry)
        }
        .sheet(isPresented: $showSavePresetSheet) {
            SavePresetSheet(onSave: savePreset)
        }
        .alert("Delete Preset", isPresented: $showDeleteConfirmation, presenting: presetToDelete) { preset in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deletePreset(preset) }
        } message: { preset in
            Text("Are you sure you want to delete \"\(preset.name)\"?")
        }
    }

    // MARK: - Helpers

    private func binding(for entry: MpvConfigEntry) -> Binding<MpvConfigEntry> {
        Binding(
            get: { entries.first { $0.id == entry.id } ?? entry },
            set: { newValue in
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index] = newValue
                    saveData()
                }
            }
        )
    }

    @ViewBuilder
    private func helpRow(key: String, value: String, description: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue)
            Text("=")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("(\(description))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Data Management

    private func loadData() {
        entries = UserDefaults.standard.getMpvConfigEntries()
        presets = UserDefaults.standard.getMpvPresets()
    }

    private func saveData() {
        UserDefaults.standard.setMpvConfigEntries(entries)
    }

    private func addEntry(_ entry: MpvConfigEntry) {
        entries.append(entry)
        saveData()
    }

    private func updateEntry(_ entry: MpvConfigEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveData()
        }
    }

    private func deleteEntry(_ entry: MpvConfigEntry) {
        entries.removeAll { $0.id == entry.id }
        saveData()
    }

    private func loadPreset(_ preset: MpvPreset) {
        entries = preset.entries
        saveData()
    }

    private func savePreset(name: String) {
        UserDefaults.standard.saveMpvPreset(name: name)
        presets = UserDefaults.standard.getMpvPresets()
    }

    private func deletePreset(_ preset: MpvPreset) {
        UserDefaults.standard.deleteMpvPreset(name: preset.name)
        presets = UserDefaults.standard.getMpvPresets()
    }
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: MpvPreset
    let isLast: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(preset.entriesCount) properties")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Load") { onLoad() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !isLast {
                Divider()
                    .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Config Entry Row

private struct MpvConfigEntryRow: View {
    @Binding var entry: MpvConfigEntry
    let isLast: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: $entry.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.key)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(entry.isEnabled ? .primary : .secondary)
                    Text(entry.value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !isLast {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }
}

// MARK: - Entry Editor

struct MpvConfigEntryEditor: View {
    var entry: MpvConfigEntry?
    let onSave: (MpvConfigEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var value = ""

    private var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text(isEditing ? "Edit Property" : "Add Property")
                .font(.system(size: 16, weight: .semibold))

            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Property Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g., hwdec", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Value")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g., videotoolbox", text: $value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button(isEditing ? "Save" : "Add") {
                    let newEntry = MpvConfigEntry(
                        id: entry?.id ?? UUID(),
                        key: key.trimmingCharacters(in: .whitespaces),
                        value: value.trimmingCharacters(in: .whitespaces),
                        isEnabled: entry?.isEnabled ?? true
                    )
                    onSave(newEntry)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty ||
                         value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
        .onAppear {
            if let entry = entry {
                key = entry.key
                value = entry.value
            }
        }
    }
}

// MARK: - Save Preset Sheet

private struct SavePresetSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Preset")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Preset Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Enter preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Save") {
                    onSave(presetName.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

#if DEBUG
struct MpvConfigView_Previews: PreviewProvider {
    static var previews: some View {
        MpvConfigView()
    }
}
#endif
