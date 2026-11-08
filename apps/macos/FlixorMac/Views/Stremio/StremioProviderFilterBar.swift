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
            HStack(spacing: DS.Space.s10) {
                providerChip(title: "All", subtitle: nil, id: "all")

                ForEach(providers) { provider in
                    providerChip(
                        title: provider.addonName,
                        subtitle: provider.streams.isEmpty ? provider.error : "\(provider.streams.count) source\(provider.streams.count == 1 ? "" : "s")",
                        id: provider.installationId
                    )
                }
            }
            .padding(.vertical, DS.Space.s4)
        }
    }

    private func providerChip(title: String, subtitle: String?, id: String) -> some View {
        Button(action: { selectedProvider = id }) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(title)
                    .font(.flixor(.footnote, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.flixor(.micro))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous)
                    .fill(selectedProvider == id ? Color.orange.opacity(0.18) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous)
                    .stroke(selectedProvider == id ? Color.orange.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
