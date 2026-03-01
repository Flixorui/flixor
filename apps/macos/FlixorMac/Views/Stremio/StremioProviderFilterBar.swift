//
//  StremioProviderFilterBar.swift
//  FlixorMac
//

import SwiftUI

struct StremioProviderFilterBar: View {
    let providers: [StremioAddonStreamResult]
    @Binding var selectedProvider: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                providerChip(title: "All", subtitle: nil, id: "all")

                ForEach(providers) { provider in
                    providerChip(
                        title: provider.addonName,
                        subtitle: provider.streams.isEmpty ? provider.error : "\(provider.streams.count) source\(provider.streams.count == 1 ? "" : "s")",
                        id: provider.installationId
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func providerChip(title: String, subtitle: String?, id: String) -> some View {
        Button(action: { selectedProvider = id }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedProvider == id ? Color.orange.opacity(0.18) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selectedProvider == id ? Color.orange.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
